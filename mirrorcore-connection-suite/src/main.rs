mod adb;
mod control;
mod mcb1;
mod video;

use std::time::Duration;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};

const DEFAULT_HOST: &str = "127.0.0.1";
const CONTROL_PORT: u16 = 27183;
const VIDEO_PORT: u16 = 27184;

#[derive(Parser, Debug)]
#[command(name = "mirrorcore-connection-suite")]
#[command(about = "Host-side connection tools for MirrorCore Android Agent", long_about = None)]
struct Cli {
    #[command(subcommand)]
    cmd: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// List connected adb devices.
    Devices,

    /// Set up adb port forwards for control/video.
    Forward {
        #[arg(long)]
        serial: Option<String>,
    },

    /// Remove adb port forwards for control/video.
    Unforward {
        #[arg(long)]
        serial: Option<String>,
    },

    /// Perform MCB1 HELLO handshake over control channel.
    Hello {
        #[arg(long)]
        serial: Option<String>,

        #[arg(long, default_value = DEFAULT_HOST)]
        host: String,

        #[arg(long, default_value_t = CONTROL_PORT)]
        port: u16,
    },

    /// Send PING over control channel and expect PONG.
    Ping {
        #[arg(long)]
        serial: Option<String>,

        #[arg(long, default_value = DEFAULT_HOST)]
        host: String,

        #[arg(long, default_value_t = CONTROL_PORT)]
        port: u16,

        #[arg(long, default_value_t = 123)]
        echo_us: u64,
    },

    /// Capture H.264 stream from the video channel into a .h264 file.
    Capture {
        #[arg(long)]
        serial: Option<String>,

        #[arg(long, default_value = DEFAULT_HOST)]
        host: String,

        #[arg(long, default_value_t = VIDEO_PORT)]
        port: u16,

        #[arg(long, default_value = "capture.h264")]
        out: String,

        /// Capture duration in seconds.
        #[arg(long)]
        seconds: Option<u64>,

        /// Capture at most this many frames.
        #[arg(long)]
        frames: Option<u64>,

        /// If set, do not run adb forward automatically.
        #[arg(long, default_value_t = false)]
        no_adb: bool,
    },

    /// Mirror to stdout as raw AnnexB H.264 (pipe to ffplay).
    Mirror {
        #[arg(long)]
        serial: Option<String>,

        #[arg(long, default_value = DEFAULT_HOST)]
        host: String,

        #[arg(long, default_value_t = VIDEO_PORT)]
        port: u16,

        /// If set, do not run adb forward automatically.
        #[arg(long, default_value_t = false)]
        no_adb: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Command::Devices => {
            let devs = adb::list_devices()?;
            if devs.is_empty() {
                println!("(no devices)");
            } else {
                for d in devs {
                    println!("{}", d.description);
                }
            }
        }
        Command::Forward { serial } => {
            let serial = resolve_serial(serial)?;
            adb::forward(&serial, CONTROL_PORT, CONTROL_PORT)?;
            adb::forward(&serial, VIDEO_PORT, VIDEO_PORT)?;
            println!("forwarded control tcp:{CONTROL_PORT} and video tcp:{VIDEO_PORT} for {serial}");
        }
        Command::Unforward { serial } => {
            let serial = resolve_serial(serial)?;
            adb::remove_forward(&serial, CONTROL_PORT).ok();
            adb::remove_forward(&serial, VIDEO_PORT).ok();
            println!("removed forwards for {serial}");
        }
        Command::Hello { serial, host, port } => {
            let serial = resolve_serial(serial)?;
            adb::forward(&serial, CONTROL_PORT, CONTROL_PORT).ok();

            let mut c = control::ControlClient::connect(&host, port)?;
            let resp = c.hello("MirrorCoreHost", 0x1122_3344_5566_7788)?;
            println!(
                "HELLO from device: role={:?} caps=0x{:08x} device_name={} nonce={}",
                resp.role, resp.caps, resp.device_name, resp.session_nonce
            );
        }
        Command::Ping {
            serial,
            host,
            port,
            echo_us,
        } => {
            let serial = resolve_serial(serial)?;
            adb::forward(&serial, CONTROL_PORT, CONTROL_PORT).ok();
            let mut c = control::ControlClient::connect(&host, port)?;
            let pong = c.ping(echo_us)?;
            println!("PONG echo_timestamp_us={}", pong.echo_timestamp_us);
        }
        Command::Capture {
            serial,
            host,
            port,
            out,
            seconds,
            frames,
            no_adb,
        } => {
            let serial = resolve_serial(serial)?;
            if !no_adb {
                adb::forward(&serial, CONTROL_PORT, CONTROL_PORT).ok();
                adb::forward(&serial, VIDEO_PORT, VIDEO_PORT).ok();
            }

            // Best-effort hello before capture.
            if let Ok(mut c) = control::ControlClient::connect(DEFAULT_HOST, CONTROL_PORT) {
                let _ = c.hello("MirrorCoreHost", 0x99aa_bbcc_ddee_ff00);
            }

            video::capture_h264(video::VideoCaptureConfig {
                host,
                port,
                out_path: out,
                duration: seconds.map(Duration::from_secs),
                frame_limit: frames,
            })?;
        }
        Command::Mirror {
            serial,
            host,
            port,
            no_adb,
        } => {
            let serial = resolve_serial(serial)?;
            if !no_adb {
                adb::forward(&serial, CONTROL_PORT, CONTROL_PORT).ok();
                adb::forward(&serial, VIDEO_PORT, VIDEO_PORT).ok();
            }

            if let Ok(mut c) = control::ControlClient::connect(DEFAULT_HOST, CONTROL_PORT) {
                let _ = c.hello("MirrorCoreHost", 0x0102_0304_0506_0708);
            }

            video::mirror_h264_to_stdout(video::VideoMirrorConfig { host, port })?;
        }
    }
    Ok(())
}

fn resolve_serial(given: Option<String>) -> Result<String> {
    if let Some(s) = given {
        return Ok(s);
    }
    let devs = adb::list_devices().context("listing adb devices")?;
    if devs.len() == 1 {
        return Ok(devs[0].serial.clone());
    }
    if devs.is_empty() {
        anyhow::bail!("no adb devices; connect a device or pass --serial");
    }
    anyhow::bail!("multiple adb devices; pass --serial");
}
