pub const MAGIC: [u8; 4] = *b"MCB1";
pub const VERSION: u8 = 1;

pub const HEADER_LEN_V1: usize = 32;
pub const MAX_HEADER_LEN: usize = 256;
pub const MAX_PAYLOAD: usize = 16 * 1024 * 1024; // 16 MiB

