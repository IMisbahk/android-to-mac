use crate::constants::{HEADER_LEN_V1, MAGIC, MAX_HEADER_LEN, MAX_PAYLOAD, VERSION};
use crate::error::{ProtocolError, Result};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Header {
    pub magic: [u8; 4],
    pub version: u8,
    pub msg_type: u8,
    pub flags: u16,
    pub header_len: u16,
    pub reserved: u16,
    pub payload_len: u32,
    pub seq: u32,
    pub timestamp_us: u64,
    pub crc32c: u32,
}

impl Header {
    pub const CRC_OFFSET: usize = 28;

    pub fn new(msg_type: u8, flags: u16, seq: u32, timestamp_us: u64, payload_len: u32) -> Self {
        Self {
            magic: MAGIC,
            version: VERSION,
            msg_type,
            flags,
            header_len: HEADER_LEN_V1 as u16,
            reserved: 0,
            payload_len,
            seq,
            timestamp_us,
            crc32c: 0,
        }
    }

    pub fn decode_base(bytes: &[u8; HEADER_LEN_V1]) -> Result<Self> {
        let magic: [u8; 4] = bytes[0..4].try_into().unwrap();
        let version = bytes[4];
        let msg_type = bytes[5];
        let flags = u16::from_le_bytes(bytes[6..8].try_into().unwrap());
        let header_len = u16::from_le_bytes(bytes[8..10].try_into().unwrap());
        let reserved = u16::from_le_bytes(bytes[10..12].try_into().unwrap());
        let payload_len = u32::from_le_bytes(bytes[12..16].try_into().unwrap());
        let seq = u32::from_le_bytes(bytes[16..20].try_into().unwrap());
        let timestamp_us = u64::from_le_bytes(bytes[20..28].try_into().unwrap());
        let crc32c = u32::from_le_bytes(bytes[28..32].try_into().unwrap());

        Ok(Self {
            magic,
            version,
            msg_type,
            flags,
            header_len,
            reserved,
            payload_len,
            seq,
            timestamp_us,
            crc32c,
        })
    }

    pub fn validate_sans_crc(&self) -> Result<()> {
        if self.magic != MAGIC {
            return Err(ProtocolError::InvalidMagic);
        }
        if self.version != VERSION {
            return Err(ProtocolError::UnsupportedVersion(self.version));
        }

        let header_len = self.header_len as usize;
        if header_len < HEADER_LEN_V1 || header_len > MAX_HEADER_LEN {
            return Err(ProtocolError::InvalidHeaderLen(self.header_len));
        }

        if self.reserved != 0 {
            return Err(ProtocolError::InvalidReserved(self.reserved));
        }

        if self.payload_len as usize > MAX_PAYLOAD {
            return Err(ProtocolError::PayloadTooLarge(self.payload_len));
        }

        Ok(())
    }

    pub fn encode_base_with_crc(&self, crc32c: u32) -> [u8; HEADER_LEN_V1] {
        let mut out = [0u8; HEADER_LEN_V1];
        out[0..4].copy_from_slice(&self.magic);
        out[4] = self.version;
        out[5] = self.msg_type;
        out[6..8].copy_from_slice(&self.flags.to_le_bytes());
        out[8..10].copy_from_slice(&self.header_len.to_le_bytes());
        out[10..12].copy_from_slice(&self.reserved.to_le_bytes());
        out[12..16].copy_from_slice(&self.payload_len.to_le_bytes());
        out[16..20].copy_from_slice(&self.seq.to_le_bytes());
        out[20..28].copy_from_slice(&self.timestamp_us.to_le_bytes());
        out[28..32].copy_from_slice(&crc32c.to_le_bytes());
        out
    }
}

