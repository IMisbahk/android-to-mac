#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MsgType {
    Hello = 0x01,
    Ping = 0x02,
    Pong = 0x03,

    VideoConfig = 0x10,
    VideoFrame = 0x11,
    AudioConfig = 0x12,
    AudioFrame = 0x13,

    InputEvent = 0x20,
    ClipboardSync = 0x30,

    FileOffer = 0x40,
    FileChunk = 0x41,
    FileEnd = 0x42,
    FileCancel = 0x43,

    ShellExec = 0x50,
    ShellOutput = 0x51,
}

impl MsgType {
    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            0x01 => Self::Hello,
            0x02 => Self::Ping,
            0x03 => Self::Pong,
            0x10 => Self::VideoConfig,
            0x11 => Self::VideoFrame,
            0x12 => Self::AudioConfig,
            0x13 => Self::AudioFrame,
            0x20 => Self::InputEvent,
            0x30 => Self::ClipboardSync,
            0x40 => Self::FileOffer,
            0x41 => Self::FileChunk,
            0x42 => Self::FileEnd,
            0x43 => Self::FileCancel,
            0x50 => Self::ShellExec,
            0x51 => Self::ShellOutput,
            _ => return None,
        })
    }
}

pub mod flags {
    pub const ACK_REQ: u16 = 0x0001;
    pub const ACK: u16 = 0x0002;
    pub const KEYFRAME: u16 = 0x0004;
    pub const COMPRESSED: u16 = 0x0008;
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Android = 1,
    Mac = 2,
}

impl Role {
    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            1 => Self::Android,
            2 => Self::Mac,
            _ => return None,
        })
    }
}

pub mod caps {
    pub const VIDEO: u32 = 0x0000_0001;
    pub const INPUT: u32 = 0x0000_0002;
    pub const CLIPBOARD: u32 = 0x0000_0004;
    pub const FILE: u32 = 0x0000_0008;
}
