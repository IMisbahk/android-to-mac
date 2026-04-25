use crate::enums::Role;
use crate::error::{ProtocolError, Result};
use crate::payload::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hello {
    pub role: Role,
    pub caps: u32,
    pub device_name: String,
    pub session_nonce: u64,
}

impl Hello {
    pub fn to_payload(&self) -> Result<Vec<u8>> {
        let mut out = Vec::new();
        write_u8(&mut out, self.role as u8);
        write_u32_le(&mut out, self.caps);
        write_str_u16(&mut out, &self.device_name)?;
        write_u64_le(&mut out, self.session_nonce);
        Ok(out)
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let role = read_u8(&mut buf)?;
        let role = Role::from_u8(role).ok_or_else(|| {
            ProtocolError::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, "role"))
        })?;

        let caps = read_u32_le(&mut buf)?;
        let device_name = read_str_u16(&mut buf)?;
        let session_nonce = read_u64_le(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self {
            role,
            caps,
            device_name,
            session_nonce,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Ping {
    pub echo_timestamp_us: u64,
}

impl Ping {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(8);
        write_u64_le(&mut out, self.echo_timestamp_us);
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let echo_timestamp_us = read_u64_le(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self { echo_timestamp_us })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardSync {
    pub origin: Role,
    pub clip_id: u64,
    pub mime: String,
    pub data: Vec<u8>,
}

impl ClipboardSync {
    pub fn to_payload(&self) -> Result<Vec<u8>> {
        let mut out = Vec::new();
        write_u8(&mut out, self.origin as u8);
        write_u64_le(&mut out, self.clip_id);
        write_str_u16(&mut out, &self.mime)?;
        write_bytes_u32(&mut out, &self.data);
        Ok(out)
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let origin = read_u8(&mut buf)?;
        let origin = Role::from_u8(origin).ok_or_else(|| {
            ProtocolError::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, "origin"))
        })?;

        let clip_id = read_u64_le(&mut buf)?;
        let mime = read_str_u16(&mut buf)?;
        let data = read_bytes_u32(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self {
            origin,
            clip_id,
            mime,
            data,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileOffer {
    pub transfer_id: u64,
    pub name: String,
    pub size: u64,
}

impl FileOffer {
    pub fn to_payload(&self) -> Result<Vec<u8>> {
        let mut out = Vec::new();
        write_u64_le(&mut out, self.transfer_id);
        write_str_u16(&mut out, &self.name)?;
        write_u64_le(&mut out, self.size);
        Ok(out)
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let transfer_id = read_u64_le(&mut buf)?;
        let name = read_str_u16(&mut buf)?;
        let size = read_u64_le(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self {
            transfer_id,
            name,
            size,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileChunk {
    pub transfer_id: u64,
    pub offset: u64,
    pub data: Vec<u8>,
}

impl FileChunk {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u64_le(&mut out, self.transfer_id);
        write_u64_le(&mut out, self.offset);
        write_bytes_u32(&mut out, &self.data);
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let transfer_id = read_u64_le(&mut buf)?;
        let offset = read_u64_le(&mut buf)?;
        let data = read_bytes_u32(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self {
            transfer_id,
            offset,
            data,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEnd {
    pub transfer_id: u64,
    pub sha256: Option<[u8; 32]>,
}

impl FileEnd {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u64_le(&mut out, self.transfer_id);
        if let Some(hash) = self.sha256 {
            out.extend_from_slice(&hash);
        }
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let transfer_id = read_u64_le(&mut buf)?;
        let sha256 = if buf.is_empty() {
            None
        } else {
            if buf.len() < 32 {
                return Err(ProtocolError::Io(std::io::Error::new(
                    std::io::ErrorKind::UnexpectedEof,
                    "sha256",
                )));
            }
            let hash: [u8; 32] = buf[0..32].try_into().unwrap();
            buf = &buf[32..];
            Some(hash)
        };
        ensure_empty(buf)?;
        Ok(Self { transfer_id, sha256 })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FileCancel {
    pub transfer_id: u64,
}

impl FileCancel {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(8);
        write_u64_le(&mut out, self.transfer_id);
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let transfer_id = read_u64_le(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self { transfer_id })
    }
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VideoCodec {
    H264 = 1,
}

impl VideoCodec {
    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            1 => Self::H264,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoConfig {
    pub codec: VideoCodec,
    pub width: u16,
    pub height: u16,
    pub fps_times_1000: u32,
    pub sps: Vec<u8>,
    pub pps: Vec<u8>,
}

impl VideoConfig {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u8(&mut out, self.codec as u8);
        write_u16_le(&mut out, self.width);
        write_u16_le(&mut out, self.height);
        write_u32_le(&mut out, self.fps_times_1000);
        write_bytes_u32(&mut out, &self.sps);
        write_bytes_u32(&mut out, &self.pps);
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let codec = read_u8(&mut buf)?;
        let codec = VideoCodec::from_u8(codec).ok_or_else(|| {
            ProtocolError::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, "codec"))
        })?;
        let width = read_u16_le(&mut buf)?;
        let height = read_u16_le(&mut buf)?;
        let fps_times_1000 = read_u32_le(&mut buf)?;
        let sps = read_bytes_u32(&mut buf)?;
        let pps = read_bytes_u32(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self {
            codec,
            width,
            height,
            fps_times_1000,
            sps,
            pps,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoFrame {
    pub pts_us: u64,
    pub data: Vec<u8>,
}

impl VideoFrame {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u64_le(&mut out, self.pts_us);
        write_bytes_u32(&mut out, &self.data);
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let pts_us = read_u64_le(&mut buf)?;
        let data = read_bytes_u32(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self { pts_us, data })
    }
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioCodec {
    PcmS16le = 1,
}

impl AudioCodec {
    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            1 => Self::PcmS16le,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioConfig {
    pub codec: AudioCodec,
    pub sample_rate: u32,
    pub channels: u8,
    pub frame_samples: u16,
    pub reserved: u16,
}

impl AudioConfig {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u8(&mut out, self.codec as u8);
        write_u32_le(&mut out, self.sample_rate);
        write_u8(&mut out, self.channels);
        write_u16_le(&mut out, self.frame_samples);
        write_u16_le(&mut out, self.reserved);
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let codec = read_u8(&mut buf)?;
        let codec = AudioCodec::from_u8(codec).ok_or_else(|| {
            ProtocolError::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, "audio.codec"))
        })?;
        let sample_rate = read_u32_le(&mut buf)?;
        let channels = read_u8(&mut buf)?;
        let frame_samples = read_u16_le(&mut buf)?;
        let reserved = read_u16_le(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self {
            codec,
            sample_rate,
            channels,
            frame_samples,
            reserved,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioFrame {
    pub pts_us: u64,
    pub data: Vec<u8>,
}

impl AudioFrame {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u64_le(&mut out, self.pts_us);
        write_bytes_u32(&mut out, &self.data);
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let pts_us = read_u64_le(&mut buf)?;
        let data = read_bytes_u32(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self { pts_us, data })
    }
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputKind {
    Touch = 1,
    Key = 2,
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TouchAction {
    Down = 0,
    Move = 1,
    Up = 2,
    Cancel = 3,
}

impl TouchAction {
    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            0 => Self::Down,
            1 => Self::Move,
            2 => Self::Up,
            3 => Self::Cancel,
            _ => return None,
        })
    }
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyAction {
    Down = 0,
    Up = 1,
}

impl KeyAction {
    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            0 => Self::Down,
            1 => Self::Up,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TouchEvent {
    pub action: TouchAction,
    pub pointer_id: u8,
    pub x_norm: f32,
    pub y_norm: f32,
    pub pressure: f32,
    pub buttons: u16,
    pub reserved: u16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyEvent {
    pub action: KeyAction,
    pub android_keycode: u32,
    pub meta_state: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum InputEvent {
    Touch(TouchEvent),
    Key(KeyEvent),
}

impl InputEvent {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::new();
        match self {
            InputEvent::Touch(t) => {
                write_u8(&mut out, InputKind::Touch as u8);
                write_u8(&mut out, t.action as u8);
                write_u8(&mut out, t.pointer_id);
                write_f32_le(&mut out, t.x_norm);
                write_f32_le(&mut out, t.y_norm);
                write_f32_le(&mut out, t.pressure);
                write_u16_le(&mut out, t.buttons);
                write_u16_le(&mut out, t.reserved);
            }
            InputEvent::Key(k) => {
                write_u8(&mut out, InputKind::Key as u8);
                write_u8(&mut out, k.action as u8);
                write_u32_le(&mut out, k.android_keycode);
                write_u32_le(&mut out, k.meta_state);
            }
        }
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let kind = read_u8(&mut buf)?;
        match kind {
            1 => {
                let action = read_u8(&mut buf)?;
                let action = TouchAction::from_u8(action).ok_or_else(|| {
                    ProtocolError::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, "touch.action"))
                })?;
                let pointer_id = read_u8(&mut buf)?;
                let x_norm = read_f32_le(&mut buf)?;
                let y_norm = read_f32_le(&mut buf)?;
                let pressure = read_f32_le(&mut buf)?;
                let buttons = read_u16_le(&mut buf)?;
                let reserved = read_u16_le(&mut buf)?;
                ensure_empty(buf)?;
                Ok(InputEvent::Touch(TouchEvent {
                    action,
                    pointer_id,
                    x_norm,
                    y_norm,
                    pressure,
                    buttons,
                    reserved,
                }))
            }
            2 => {
                let action = read_u8(&mut buf)?;
                let action = KeyAction::from_u8(action).ok_or_else(|| {
                    ProtocolError::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, "key.action"))
                })?;
                let android_keycode = read_u32_le(&mut buf)?;
                let meta_state = read_u32_le(&mut buf)?;
                ensure_empty(buf)?;
                Ok(InputEvent::Key(KeyEvent {
                    action,
                    android_keycode,
                    meta_state,
                }))
            }
            _ => Err(ProtocolError::Io(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "input.kind",
            ))),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShellExec {
    pub command: String,
}

impl ShellExec {
    pub fn to_payload(&self) -> Result<Vec<u8>> {
        let mut out = Vec::new();
        write_str_u16(&mut out, &self.command)?;
        Ok(out)
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let command = read_str_u16(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self { command })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShellOutput {
    pub exit_code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl ShellOutput {
    pub fn to_payload(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_u32_le(&mut out, self.exit_code as u32);
        write_bytes_u32(&mut out, &self.stdout);
        write_bytes_u32(&mut out, &self.stderr);
        out
    }

    pub fn from_payload(mut buf: &[u8]) -> Result<Self> {
        let exit_code = read_u32_le(&mut buf)? as i32;
        let stdout = read_bytes_u32(&mut buf)?;
        let stderr = read_bytes_u32(&mut buf)?;
        ensure_empty(buf)?;
        Ok(Self {
            exit_code,
            stdout,
            stderr,
        })
    }
}

fn ensure_empty(buf: &[u8]) -> Result<()> {
    if buf.is_empty() {
        Ok(())
    } else {
        Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "trailing bytes",
        )))
    }
}
