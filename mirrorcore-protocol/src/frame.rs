use crate::constants::{HEADER_LEN_V1, MAX_HEADER_LEN};
use crate::error::{ProtocolError, Result};
use crate::header::Header;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub header: Header,
    pub header_extra: Vec<u8>,
    pub payload: Vec<u8>,
}

impl Frame {
    pub fn new(header: Header, payload: Vec<u8>) -> Result<Self> {
        if header.payload_len != payload.len() as u32 {
            return Err(ProtocolError::PayloadLenMismatch {
                header: header.payload_len,
                actual: payload.len(),
            });
        }

        Ok(Self {
            header,
            header_extra: Vec::new(),
            payload,
        })
    }

    pub fn with_header_extra(mut self, header_extra: Vec<u8>) -> Result<Self> {
        let total = HEADER_LEN_V1 + header_extra.len();
        if total > MAX_HEADER_LEN {
            return Err(ProtocolError::InvalidHeaderLen(total as u16));
        }
        self.header.header_len = total as u16;
        self.header_extra = header_extra;
        Ok(self)
    }
}

