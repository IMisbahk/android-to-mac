use crate::error::{ProtocolError, Result};

pub fn read_u8(buf: &mut &[u8]) -> Result<u8> {
    if buf.is_empty() {
        return Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "u8",
        )));
    }
    let v = buf[0];
    *buf = &buf[1..];
    Ok(v)
}

pub fn read_u16_le(buf: &mut &[u8]) -> Result<u16> {
    if buf.len() < 2 {
        return Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "u16",
        )));
    }
    let v = u16::from_le_bytes(buf[0..2].try_into().unwrap());
    *buf = &buf[2..];
    Ok(v)
}

pub fn read_u32_le(buf: &mut &[u8]) -> Result<u32> {
    if buf.len() < 4 {
        return Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "u32",
        )));
    }
    let v = u32::from_le_bytes(buf[0..4].try_into().unwrap());
    *buf = &buf[4..];
    Ok(v)
}

pub fn read_u64_le(buf: &mut &[u8]) -> Result<u64> {
    if buf.len() < 8 {
        return Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "u64",
        )));
    }
    let v = u64::from_le_bytes(buf[0..8].try_into().unwrap());
    *buf = &buf[8..];
    Ok(v)
}

pub fn read_f32_le(buf: &mut &[u8]) -> Result<f32> {
    if buf.len() < 4 {
        return Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "f32",
        )));
    }
    let v = f32::from_le_bytes(buf[0..4].try_into().unwrap());
    *buf = &buf[4..];
    Ok(v)
}

pub fn read_bytes_u16(buf: &mut &[u8]) -> Result<Vec<u8>> {
    let len = read_u16_le(buf)? as usize;
    if buf.len() < len {
        return Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "bytes(u16)",
        )));
    }
    let out = buf[0..len].to_vec();
    *buf = &buf[len..];
    Ok(out)
}

pub fn read_bytes_u32(buf: &mut &[u8]) -> Result<Vec<u8>> {
    let len = read_u32_le(buf)? as usize;
    if buf.len() < len {
        return Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "bytes(u32)",
        )));
    }
    let out = buf[0..len].to_vec();
    *buf = &buf[len..];
    Ok(out)
}

pub fn read_str_u16(buf: &mut &[u8]) -> Result<String> {
    let bytes = read_bytes_u16(buf)?;
    String::from_utf8(bytes).map_err(|e| ProtocolError::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, e)))
}

pub fn write_u8(out: &mut Vec<u8>, v: u8) {
    out.push(v);
}

pub fn write_u16_le(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_le_bytes());
}

pub fn write_u32_le(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}

pub fn write_u64_le(out: &mut Vec<u8>, v: u64) {
    out.extend_from_slice(&v.to_le_bytes());
}

pub fn write_f32_le(out: &mut Vec<u8>, v: f32) {
    out.extend_from_slice(&v.to_le_bytes());
}

pub fn write_bytes_u16(out: &mut Vec<u8>, bytes: &[u8]) -> Result<()> {
    if bytes.len() > u16::MAX as usize {
        return Err(ProtocolError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "bytes too long for u16 length",
        )));
    }
    write_u16_le(out, bytes.len() as u16);
    out.extend_from_slice(bytes);
    Ok(())
}

pub fn write_bytes_u32(out: &mut Vec<u8>, bytes: &[u8]) {
    write_u32_le(out, bytes.len() as u32);
    out.extend_from_slice(bytes);
}

pub fn write_str_u16(out: &mut Vec<u8>, s: &str) -> Result<()> {
    write_bytes_u16(out, s.as_bytes())
}

