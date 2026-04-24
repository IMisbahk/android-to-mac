use std::fs::File;
use std::io::{BufReader, BufWriter, Write};
use std::net::TcpStream;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use mirrorcore_protocol::enums::MsgType;
use mirrorcore_protocol::types::{VideoConfig, VideoFrame};

use crate::mcb1::Mcb1Stream;

pub struct VideoCaptureConfig {
    pub host: String,
    pub port: u16,
    pub out_path: String,
    pub duration: Option<Duration>,
    pub frame_limit: Option<u64>,
}

pub fn capture_h264(cfg: VideoCaptureConfig) -> Result<()> {
    let stream = TcpStream::connect((&*cfg.host, cfg.port)).with_context(|| format!("connect video {}:{}", cfg.host, cfg.port))?;
    stream.set_nodelay(true).ok();
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .ok();

    let mcb1 = Mcb1Stream::default();
    let mut reader = BufReader::new(stream);

    let mut out = BufWriter::new(File::create(&cfg.out_path).with_context(|| format!("create {}", cfg.out_path))?);

    let start = Instant::now();
    let mut got_config = false;
    let mut frames: u64 = 0;
    let mut bytes: u64 = 0;
    let mut last_log = Instant::now();

    loop {
        if let Some(dur) = cfg.duration {
            if start.elapsed() >= dur {
                break;
            }
        }
        if let Some(limit) = cfg.frame_limit {
            if frames >= limit {
                break;
            }
        }

        let frame = mcb1.read_frame(&mut reader)?;
        match frame.header.msg_type {
            x if x == MsgType::VideoConfig as u8 => {
                let vc = VideoConfig::from_payload(&frame.payload)?;
                eprintln!(
                    "VIDEO_CONFIG codec={:?} {}x{} fps*1000={} sps={}B pps={}B",
                    vc.codec,
                    vc.width,
                    vc.height,
                    vc.fps_times_1000,
                    vc.sps.len(),
                    vc.pps.len()
                );
                got_config = true;
            }
            x if x == MsgType::VideoFrame as u8 => {
                if !got_config {
                    // Still write the stream, but warn once.
                    eprintln!("warning: got VIDEO_FRAME before VIDEO_CONFIG");
                    got_config = true;
                }
                let vf = VideoFrame::from_payload(&frame.payload)?;
                out.write_all(&vf.data)?;
                frames += 1;
                bytes += vf.data.len() as u64;

                if last_log.elapsed() >= Duration::from_secs(1) {
                    let fps = (frames as f64) / start.elapsed().as_secs_f64().max(0.001);
                    let kbps = ((bytes as f64) * 8.0 / start.elapsed().as_secs_f64().max(0.001)) / 1000.0;
                    eprintln!("capture: frames={frames} avg_fps={fps:.1} avg_kbps={kbps:.0} last_pts_us={}", vf.pts_us);
                    last_log = Instant::now();
                }
            }
            other => {
                eprintln!("ignoring msg_type={other}");
            }
        }
    }

    out.flush()?;
    eprintln!("wrote {} bytes to {}", bytes, cfg.out_path);
    Ok(())
}

pub struct VideoMirrorConfig {
    pub host: String,
    pub port: u16,
}

pub fn mirror_h264_to_stdout(cfg: VideoMirrorConfig) -> Result<()> {
    let stream =
        TcpStream::connect((&*cfg.host, cfg.port)).with_context(|| format!("connect video {}:{}", cfg.host, cfg.port))?;
    stream.set_nodelay(true).ok();
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .ok();

    let mcb1 = Mcb1Stream::default();
    let mut reader = BufReader::new(stream);

    let stdout = std::io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    let mut got_config = false;
    loop {
        let frame = mcb1.read_frame(&mut reader)?;
        match frame.header.msg_type {
            x if x == MsgType::VideoConfig as u8 => {
                let vc = VideoConfig::from_payload(&frame.payload)?;
                eprintln!(
                    "VIDEO_CONFIG codec={:?} {}x{} fps*1000={} sps={}B pps={}B",
                    vc.codec,
                    vc.width,
                    vc.height,
                    vc.fps_times_1000,
                    vc.sps.len(),
                    vc.pps.len()
                );
                // Prepend SPS/PPS as AnnexB NALs so raw decoders can lock immediately.
                write_annexb_nal(&mut out, &vc.sps)?;
                write_annexb_nal(&mut out, &vc.pps)?;
                out.flush()?;
                got_config = true;
            }
            x if x == MsgType::VideoFrame as u8 => {
                if !got_config {
                    eprintln!("warning: got VIDEO_FRAME before VIDEO_CONFIG");
                    got_config = true;
                }
                let vf = VideoFrame::from_payload(&frame.payload)?;
                out.write_all(&vf.data)?;
                out.flush()?;
            }
            other => {
                eprintln!("ignoring msg_type={other}");
            }
        }
    }
}

fn write_annexb_nal<W: Write>(out: &mut W, nal_no_startcode: &[u8]) -> Result<()> {
    if nal_no_startcode.is_empty() {
        return Ok(());
    }
    out.write_all(&[0, 0, 0, 1])?;
    out.write_all(nal_no_startcode)?;
    Ok(())
}
