use std::io::{Cursor, Read};

use mirrorcore_protocol::{
    constants::{HEADER_LEN_V1, MAX_PAYLOAD, VERSION},
    enums::MsgType,
    error::ProtocolError,
    Frame, Header, StreamCodec,
};

fn encode_frame(frame: &Frame) -> Vec<u8> {
    let codec = StreamCodec::default();
    let mut out = Vec::new();
    codec.write_frame(&mut out, frame).unwrap();
    out
}

fn decode_frame(bytes: &[u8]) -> Result<Frame, ProtocolError> {
    let codec = StreamCodec::default();
    let mut cur = Cursor::new(bytes);
    codec.read_frame(&mut cur)
}

#[test]
fn header_frame_roundtrip_ok() {
    let header = Header::new(MsgType::Ping as u8, 0, 42, 123_456, 8);
    let payload = 123_456u64.to_le_bytes().to_vec();
    let frame = Frame::new(header.clone(), payload.clone()).unwrap();

    let bytes = encode_frame(&frame);
    let decoded = decode_frame(&bytes).unwrap();

    assert_eq!(decoded.header.magic, *b"MCB1");
    assert_eq!(decoded.header.version, VERSION);
    assert_eq!(decoded.header.msg_type, MsgType::Ping as u8);
    assert_eq!(decoded.header.flags, 0);
    assert_eq!(decoded.header.header_len as usize, HEADER_LEN_V1);
    assert_eq!(decoded.header.payload_len, payload.len() as u32);
    assert_eq!(decoded.header.seq, header.seq);
    assert_eq!(decoded.header.timestamp_us, header.timestamp_us);
    assert_eq!(decoded.payload, payload);
}

#[test]
fn unknown_msg_type_is_not_fatal() {
    let header = Header::new(0x99, 0, 1, 2, 3);
    let payload = vec![1, 2, 3];
    let frame = Frame::new(header, payload.clone()).unwrap();

    let decoded = decode_frame(&encode_frame(&frame)).unwrap();
    assert_eq!(decoded.header.msg_type, 0x99);
    assert_eq!(decoded.payload, payload);
}

#[test]
fn crc_mismatch_detected() {
    let header = Header::new(MsgType::ClipboardSync as u8, 0, 1, 2, 3);
    let payload = vec![0xAA, 0xBB, 0xCC];
    let frame = Frame::new(header, payload).unwrap();
    let mut bytes = encode_frame(&frame);

    // Flip one bit in the payload.
    let last = bytes.len() - 1;
    bytes[last] ^= 0b0000_0001;

    let err = decode_frame(&bytes).unwrap_err();
    match err {
        ProtocolError::CrcMismatch { .. } => {}
        other => panic!("expected crc mismatch, got {other:?}"),
    }
}

#[test]
fn reject_bad_magic() {
    let header = Header::new(MsgType::Ping as u8, 0, 1, 1, 0);
    let frame = Frame::new(header, vec![]).unwrap();
    let mut bytes = encode_frame(&frame);
    bytes[0] = b'X';

    let err = decode_frame(&bytes).unwrap_err();
    assert!(matches!(err, ProtocolError::InvalidMagic));
}

#[test]
fn reject_payload_too_large_without_reading_payload() {
    let mut hdr = [0u8; HEADER_LEN_V1];
    hdr[0..4].copy_from_slice(b"MCB1");
    hdr[4] = VERSION;
    hdr[5] = MsgType::Ping as u8;
    hdr[6..8].copy_from_slice(&0u16.to_le_bytes());
    hdr[8..10].copy_from_slice(&(HEADER_LEN_V1 as u16).to_le_bytes());
    hdr[10..12].copy_from_slice(&0u16.to_le_bytes());
    hdr[12..16].copy_from_slice(&((MAX_PAYLOAD as u32) + 1).to_le_bytes());
    hdr[16..20].copy_from_slice(&1u32.to_le_bytes());
    hdr[20..28].copy_from_slice(&2u64.to_le_bytes());
    hdr[28..32].copy_from_slice(&0u32.to_le_bytes());

    let codec = StreamCodec::default();
    let mut cur = Cursor::new(hdr);
    let err = codec.read_frame(&mut cur).unwrap_err();
    assert!(matches!(err, ProtocolError::PayloadTooLarge(_)));
}

struct ChunkedRead<R> {
    inner: R,
    max: usize,
}

impl<R: Read> Read for ChunkedRead<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let n = buf.len().min(self.max).max(1);
        self.inner.read(&mut buf[..n])
    }
}

#[test]
fn stream_parses_under_adversarial_chunking() {
    let f1 = Frame::new(
        Header::new(MsgType::Ping as u8, 0, 1, 1, 8),
        1u64.to_le_bytes().to_vec(),
    )
    .unwrap();
    let f2 = Frame::new(
        Header::new(MsgType::Pong as u8, 0, 2, 2, 8),
        2u64.to_le_bytes().to_vec(),
    )
    .unwrap();

    let mut bytes = Vec::new();
    bytes.extend_from_slice(&encode_frame(&f1));
    bytes.extend_from_slice(&encode_frame(&f2));

    for max in 1..=7 {
        let codec = StreamCodec::default();
        let mut reader = ChunkedRead {
            inner: Cursor::new(bytes.as_slice()),
            max,
        };
        let d1 = codec.read_frame(&mut reader).unwrap();
        let d2 = codec.read_frame(&mut reader).unwrap();
        assert_eq!(d1.header.msg_type, MsgType::Ping as u8);
        assert_eq!(d2.header.msg_type, MsgType::Pong as u8);
    }
}
