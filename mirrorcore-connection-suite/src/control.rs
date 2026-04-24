use std::io::{BufReader, BufWriter, Write};
use std::net::TcpStream;
use std::time::Duration;

use anyhow::{Context, Result};
use mirrorcore_protocol::enums::{caps, MsgType, Role};
use mirrorcore_protocol::types::{Hello, Ping};
use mirrorcore_protocol::Header;

use crate::mcb1::Mcb1Stream;

pub struct ControlClient {
    stream: TcpStream,
    mcb1: Mcb1Stream,
    seq: u32,
}

impl ControlClient {
    pub fn connect(host: &str, port: u16) -> Result<Self> {
        let stream = TcpStream::connect((host, port)).with_context(|| format!("connect control {host}:{port}"))?;
        stream.set_nodelay(true).ok();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .ok();
        stream
            .set_write_timeout(Some(Duration::from_secs(5)))
            .ok();

        Ok(Self {
            stream,
            mcb1: Mcb1Stream::default(),
            seq: 1,
        })
    }

    pub fn hello(&mut self, device_name: &str, session_nonce: u64) -> Result<Hello> {
        let hello = Hello {
            role: Role::Mac,
            caps: caps::VIDEO | caps::INPUT | caps::CLIPBOARD | caps::FILE,
            device_name: device_name.to_string(),
            session_nonce,
        };
        let payload = hello.to_payload()?;
        let header = Header::new(
            MsgType::Hello as u8,
            0,
            self.next_seq(),
            now_us(),
            payload.len() as u32,
        );

        let mut writer = BufWriter::new(self.stream.try_clone()?);
        self.mcb1.write_frame(&mut writer, header, payload)?;
        writer.flush()?;

        let mut reader = BufReader::new(self.stream.try_clone()?);
        let resp = self.mcb1.read_frame(&mut reader)?;
        if resp.header.msg_type != MsgType::Hello as u8 {
            anyhow::bail!("expected HELLO response, got msg_type={}", resp.header.msg_type);
        }
        Ok(Hello::from_payload(&resp.payload)?)
    }

    pub fn ping(&mut self, echo_timestamp_us: u64) -> Result<Ping> {
        let ping = Ping { echo_timestamp_us };
        let payload = ping.to_payload();
        let header = Header::new(
            MsgType::Ping as u8,
            0,
            self.next_seq(),
            now_us(),
            payload.len() as u32,
        );

        let mut writer = BufWriter::new(self.stream.try_clone()?);
        self.mcb1.write_frame(&mut writer, header, payload)?;
        writer.flush()?;

        let mut reader = BufReader::new(self.stream.try_clone()?);
        let resp = self.mcb1.read_frame(&mut reader)?;
        if resp.header.msg_type != MsgType::Pong as u8 {
            anyhow::bail!("expected PONG response, got msg_type={}", resp.header.msg_type);
        }
        Ok(Ping::from_payload(&resp.payload)?)
    }

    fn next_seq(&mut self) -> u32 {
        let s = self.seq;
        self.seq = self.seq.wrapping_add(1);
        s
    }
}

fn now_us() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros() as u64
}
