use std::fs::File;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::PathBuf;

use clap::{Parser, Subcommand, ValueEnum};
use mirrorcore_protocol::{
    enums::{caps, MsgType, Role},
    types::{Hello, Ping},
    Frame, Header, StreamCodec,
};
use serde::Serialize;

#[derive(Parser, Debug)]
#[command(name = "mirrorcore-protocol-cli")]
#[command(about = "MirrorCore MCB1 protocol encoder/decoder", long_about = None)]
struct Cli {
    #[command(subcommand)]
    cmd: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Decode frames from stdin or a file and print one JSON object per frame.
    Decode {
        #[arg(short, long)]
        input: Option<PathBuf>,

        /// Include a hex preview of the payload (first N bytes).
        #[arg(long, default_value_t = 0)]
        payload_hex_bytes: usize,
    },

    /// Encode a sample frame and write raw bytes to stdout.
    Encode {
        #[command(subcommand)]
        msg: EncodeMsg,

        #[arg(long, default_value_t = 0)]
        seq: u32,

        #[arg(long, default_value_t = 0)]
        timestamp_us: u64,

        #[arg(long, default_value_t = 0)]
        flags: u16,
    },
}

#[derive(Subcommand, Debug)]
enum EncodeMsg {
    Hello {
        #[arg(long, value_enum)]
        role: RoleArg,

        #[arg(long, default_value = "MirrorCoreDevice")]
        device_name: String,

        /// Caps, comma-separated: video,input,clipboard,file
        #[arg(long, default_value = "video,input,clipboard,file")]
        caps: String,

        #[arg(long, default_value_t = 0)]
        session_nonce: u64,
    },

    Ping {
        #[arg(long, default_value_t = 0)]
        echo_timestamp_us: u64,
        /// Use msg type PONG instead of PING.
        #[arg(long, default_value_t = false)]
        pong: bool,
    },
}

#[derive(ValueEnum, Debug, Clone, Copy)]
enum RoleArg {
    Android,
    Mac,
}

impl From<RoleArg> for Role {
    fn from(value: RoleArg) -> Self {
        match value {
            RoleArg::Android => Role::Android,
            RoleArg::Mac => Role::Mac,
        }
    }
}

#[derive(Debug, Serialize)]
struct FrameJson {
    header: HeaderJson,
    payload_len: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    payload_hex_preview: Option<String>,
}

#[derive(Debug, Serialize)]
struct HeaderJson {
    magic: String,
    version: u8,
    msg_type: u8,
    flags: u16,
    header_len: u16,
    reserved: u16,
    payload_len: u32,
    seq: u32,
    timestamp_us: u64,
    crc32c: String,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.cmd {
        Command::Decode {
            input,
            payload_hex_bytes,
        } => cmd_decode(input, payload_hex_bytes)?,
        Command::Encode {
            msg,
            seq,
            timestamp_us,
            flags,
        } => cmd_encode(msg, seq, timestamp_us, flags)?,
    }

    Ok(())
}

fn cmd_decode(input: Option<PathBuf>, payload_hex_bytes: usize) -> anyhow::Result<()> {
    let codec = StreamCodec::default();

    let reader: Box<dyn Read> = match input {
        Some(p) => Box::new(File::open(p)?),
        None => Box::new(io::stdin().lock()),
    };

    let mut reader = BufReader::new(reader);
    let mut stdout = io::stdout().lock();

    loop {
        if reader.fill_buf()?.is_empty() {
            break;
        }

        let frame = codec.read_frame(&mut reader)?;
        let json = FrameJson {
            header: HeaderJson::from_header(&frame.header),
            payload_len: frame.payload.len(),
            payload_hex_preview: if payload_hex_bytes == 0 {
                None
            } else {
                Some(hex_preview(&frame.payload, payload_hex_bytes))
            },
        };
        serde_json::to_writer(&mut stdout, &json)?;
        stdout.write_all(b"\n")?;
    }

    Ok(())
}

fn cmd_encode(msg: EncodeMsg, seq: u32, timestamp_us: u64, flags: u16) -> anyhow::Result<()> {
    let (msg_type, payload) = match msg {
        EncodeMsg::Hello {
            role,
            device_name,
            caps: caps_str,
            session_nonce,
        } => {
            let caps_bits = parse_caps(&caps_str)?;
            let hello = Hello {
                role: role.into(),
                caps: caps_bits,
                device_name,
                session_nonce,
            };
            (MsgType::Hello as u8, hello.to_payload()?)
        }
        EncodeMsg::Ping {
            echo_timestamp_us,
            pong,
        } => {
            let ping = Ping { echo_timestamp_us };
            (
                if pong { MsgType::Pong as u8 } else { MsgType::Ping as u8 },
                ping.to_payload(),
            )
        }
    };

    let header = Header::new(msg_type, flags, seq, timestamp_us, payload.len() as u32);
    let frame = Frame::new(header, payload)?;

    let codec = StreamCodec::default();
    let mut stdout = io::stdout().lock();
    codec.write_frame(&mut stdout, &frame)?;
    Ok(())
}

impl HeaderJson {
    fn from_header(h: &mirrorcore_protocol::Header) -> Self {
        Self {
            magic: String::from_utf8_lossy(&h.magic).to_string(),
            version: h.version,
            msg_type: h.msg_type,
            flags: h.flags,
            header_len: h.header_len,
            reserved: h.reserved,
            payload_len: h.payload_len,
            seq: h.seq,
            timestamp_us: h.timestamp_us,
            crc32c: format!("{:#010x}", h.crc32c),
        }
    }
}

fn parse_caps(s: &str) -> anyhow::Result<u32> {
    let mut out = 0u32;
    for raw in s.split(',').map(|p| p.trim()).filter(|p| !p.is_empty()) {
        match raw {
            "video" => out |= caps::VIDEO,
            "input" => out |= caps::INPUT,
            "clipboard" => out |= caps::CLIPBOARD,
            "file" => out |= caps::FILE,
            other => anyhow::bail!("unknown cap: {other}"),
        }
    }
    Ok(out)
}

fn hex_preview(bytes: &[u8], limit: usize) -> String {
    let n = bytes.len().min(limit);
    let mut s = String::with_capacity(n * 2);
    for b in &bytes[..n] {
        use std::fmt::Write as _;
        let _ = write!(s, "{:02x}", b);
    }
    if bytes.len() > n {
        s.push_str("…");
    }
    s
}
