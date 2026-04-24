use std::io::{Read, Write};

use crate::constants::{HEADER_LEN_V1, MAX_HEADER_LEN, MAX_PAYLOAD};
use crate::error::{ProtocolError, Result};
use crate::frame::Frame;
use crate::header::Header;

#[derive(Debug, Clone, Copy)]
pub struct StreamCodec {
    pub max_header_len: usize,
    pub max_payload: usize,
}

impl Default for StreamCodec {
    fn default() -> Self {
        Self {
            max_header_len: MAX_HEADER_LEN,
            max_payload: MAX_PAYLOAD,
        }
    }
}

impl StreamCodec {
    pub fn read_frame<R: Read>(&self, reader: &mut R) -> Result<Frame> {
        let mut base = [0u8; HEADER_LEN_V1];
        reader.read_exact(&mut base)?;

        let header = Header::decode_base(&base)?;
        header.validate_sans_crc()?;

        let header_len = header.header_len as usize;
        if header_len > self.max_header_len {
            return Err(ProtocolError::InvalidHeaderLen(header.header_len));
        }

        if header.payload_len as usize > self.max_payload {
            return Err(ProtocolError::PayloadTooLarge(header.payload_len));
        }

        let mut header_extra = vec![0u8; header_len.saturating_sub(HEADER_LEN_V1)];
        if !header_extra.is_empty() {
            reader.read_exact(&mut header_extra)?;
        }

        let mut payload = vec![0u8; header.payload_len as usize];
        if !payload.is_empty() {
            reader.read_exact(&mut payload)?;
        }

        let expected = header.crc32c;
        let actual = compute_crc32c(&base, &header_extra, &payload);
        if expected != actual {
            return Err(ProtocolError::CrcMismatch { expected, actual });
        }

        Ok(Frame {
            header,
            header_extra,
            payload,
        })
    }

    pub fn write_frame<W: Write>(&self, writer: &mut W, frame: &Frame) -> Result<()> {
        let header_len_expected = HEADER_LEN_V1 + frame.header_extra.len();
        if frame.header.header_len as usize != header_len_expected {
            return Err(ProtocolError::InvalidHeaderLen(frame.header.header_len));
        }
        if header_len_expected > self.max_header_len {
            return Err(ProtocolError::InvalidHeaderLen(frame.header.header_len));
        }

        if frame.header.payload_len as usize != frame.payload.len() {
            return Err(ProtocolError::PayloadLenMismatch {
                header: frame.header.payload_len,
                actual: frame.payload.len(),
            });
        }
        if frame.payload.len() > self.max_payload {
            return Err(ProtocolError::PayloadTooLarge(frame.payload.len() as u32));
        }

        frame.header.validate_sans_crc()?;

        let base_zero_crc = frame.header.encode_base_with_crc(0);
        let crc = compute_crc32c(&base_zero_crc, &frame.header_extra, &frame.payload);
        let base_with_crc = frame.header.encode_base_with_crc(crc);

        writer.write_all(&base_with_crc)?;
        if !frame.header_extra.is_empty() {
            writer.write_all(&frame.header_extra)?;
        }
        if !frame.payload.is_empty() {
            writer.write_all(&frame.payload)?;
        }

        Ok(())
    }
}

fn compute_crc32c(base_header: &[u8; HEADER_LEN_V1], header_extra: &[u8], payload: &[u8]) -> u32 {
    let mut hdr = Vec::with_capacity(HEADER_LEN_V1 + header_extra.len() + payload.len());
    hdr.extend_from_slice(base_header);
    hdr[Header::CRC_OFFSET..Header::CRC_OFFSET + 4].copy_from_slice(&[0, 0, 0, 0]);
    hdr.extend_from_slice(header_extra);
    hdr.extend_from_slice(payload);
    crc32c::crc32c(&hdr)
}

