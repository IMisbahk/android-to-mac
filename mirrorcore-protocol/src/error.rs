use std::io;

#[derive(Debug, thiserror::Error)]
pub enum ProtocolError {
    #[error("io: {0}")]
    Io(#[from] io::Error),

    #[error("invalid magic")]
    InvalidMagic,

    #[error("unsupported version: {0}")]
    UnsupportedVersion(u8),

    #[error("invalid header length: {0}")]
    InvalidHeaderLen(u16),

    #[error("invalid reserved field: {0}")]
    InvalidReserved(u16),

    #[error("payload too large: {0}")]
    PayloadTooLarge(u32),

    #[error("payload length mismatch: header={header} actual={actual}")]
    PayloadLenMismatch { header: u32, actual: usize },

    #[error("crc mismatch: expected={expected:#010x} actual={actual:#010x}")]
    CrcMismatch { expected: u32, actual: u32 },
}

pub type Result<T> = std::result::Result<T, ProtocolError>;

