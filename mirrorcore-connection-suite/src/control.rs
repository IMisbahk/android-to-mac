use std::io::{BufReader, BufWriter, Write};
use std::net::TcpStream;
use std::time::Duration;

use anyhow::{Context, Result};
use mirrorcore_protocol::enums::{caps, MsgType, Role};
use mirrorcore_protocol::types::{Hello, InputEvent, KeyAction, KeyEvent, Ping, TouchAction, TouchEvent};
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

    pub fn tap(&mut self, x_norm: f32, y_norm: f32) -> Result<()> {
        self.send_touch_sequence(x_norm, y_norm, x_norm, y_norm)
    }

    pub fn swipe(&mut self, x0: f32, y0: f32, x1: f32, y1: f32) -> Result<()> {
        self.send_touch_sequence(x0, y0, x1, y1)
    }

    pub fn send_key(&mut self, keycode: u32, meta_state: u32) -> Result<()> {
        let mut writer = BufWriter::new(self.stream.try_clone()?);
        let down = InputEvent::Key(KeyEvent {
            action: KeyAction::Down,
            android_keycode: keycode,
            meta_state,
        });
        self.send_input(&mut writer, down)?;
        let up = InputEvent::Key(KeyEvent {
            action: KeyAction::Up,
            android_keycode: keycode,
            meta_state,
        });
        self.send_input(&mut writer, up)?;
        writer.flush()?;
        Ok(())
    }

    fn send_touch_sequence(&mut self, x0: f32, y0: f32, x1: f32, y1: f32) -> Result<()> {
        let mut writer = BufWriter::new(self.stream.try_clone()?);

        let down = InputEvent::Touch(TouchEvent {
            action: TouchAction::Down,
            pointer_id: 0,
            x_norm: x0,
            y_norm: y0,
            pressure: 1.0,
            buttons: 0,
            reserved: 0,
        });
        self.send_input(&mut writer, down)?;

        let mv = InputEvent::Touch(TouchEvent {
            action: TouchAction::Move,
            pointer_id: 0,
            x_norm: x1,
            y_norm: y1,
            pressure: 1.0,
            buttons: 0,
            reserved: 0,
        });
        self.send_input(&mut writer, mv)?;

        let up = InputEvent::Touch(TouchEvent {
            action: TouchAction::Up,
            pointer_id: 0,
            x_norm: x1,
            y_norm: y1,
            pressure: 0.0,
            buttons: 0,
            reserved: 0,
        });
        self.send_input(&mut writer, up)?;

        writer.flush()?;
        Ok(())
    }

    fn send_input(&mut self, writer: &mut BufWriter<TcpStream>, ev: InputEvent) -> Result<()> {
        let payload = ev.to_payload();
        let header = Header::new(
            MsgType::InputEvent as u8,
            0,
            self.next_seq(),
            now_us(),
            payload.len() as u32,
        );
        self.mcb1.write_frame(writer, header, payload)?;
        Ok(())
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
