use std::io::BufReader;
use std::net::TcpStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use anyhow::{Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use mirrorcore_protocol::enums::MsgType;
use mirrorcore_protocol::types::{AudioConfig, AudioFrame, AudioCodec};
use ringbuf::traits::{Consumer, Producer, Split};
use ringbuf::HeapRb;

use crate::mcb1::Mcb1Stream;

pub struct AudioPlayConfig {
    pub host: String,
    pub port: u16,
}

pub fn play_audio(cfg: AudioPlayConfig) -> Result<()> {
    let running = Arc::new(AtomicBool::new(true));

    // Ring buffer for f32 samples.
    let rb = HeapRb::<f32>::new(48_000 * 2); // ~0.5s stereo at 48k
    let (mut prod, mut cons) = rb.split();

    let host = cpal::default_host();
    let device = host
        .default_output_device()
        .context("no default output device")?;
    let supported = device.default_output_config().context("no default output config")?;
    let sample_format = supported.sample_format();
    let config = supported.into();

    let stream = match sample_format {
        cpal::SampleFormat::F32 => device.build_output_stream(
            &config,
            move |data: &mut [f32], _| fill_f32(data, &mut cons),
            err_fn,
            None,
        )?,
        cpal::SampleFormat::I16 => device.build_output_stream(
            &config,
            move |data: &mut [i16], _| fill_i16(data, &mut cons),
            err_fn,
            None,
        )?,
        cpal::SampleFormat::U16 => device.build_output_stream(
            &config,
            move |data: &mut [u16], _| fill_u16(data, &mut cons),
            err_fn,
            None,
        )?,
        other => anyhow::bail!("unsupported output sample format: {other:?}"),
    };
    stream.play()?;

    let running_net = running.clone();
    let net_thread = thread::spawn(move || -> Result<()> {
        let mcb1 = Mcb1Stream::default();

        let mut backoff = Duration::from_millis(200);
        loop {
            if !running_net.load(Ordering::Relaxed) {
                break;
            }
            match TcpStream::connect((&*cfg.host, cfg.port)) {
                Ok(stream) => {
                    stream.set_nodelay(true).ok();
                    stream.set_read_timeout(Some(Duration::from_secs(10))).ok();
                    backoff = Duration::from_millis(200);

                    let mut reader = BufReader::new(stream);
                    let mut got_config = false;
                    loop {
                        if !running_net.load(Ordering::Relaxed) {
                            break;
                        }
                        let frame = match mcb1.read_frame(&mut reader) {
                            Ok(f) => f,
                            Err(e) => {
                                eprintln!("audio stream ended ({e}); reconnecting...");
                                break;
                            }
                        };
                        match frame.header.msg_type {
                            x if x == MsgType::AudioConfig as u8 => {
                                let ac = AudioConfig::from_payload(&frame.payload)?;
                                if ac.codec != AudioCodec::PcmS16le {
                                    eprintln!("unsupported audio codec: {:?}", ac.codec);
                                } else {
                                    eprintln!(
                                        "AUDIO_CONFIG codec={:?} rate={} ch={} frame_samples={}",
                                        ac.codec, ac.sample_rate, ac.channels, ac.frame_samples
                                    );
                                }
                                got_config = true;
                            }
                            x if x == MsgType::AudioFrame as u8 => {
                                if !got_config {
                                    // tolerate out-of-order
                                    got_config = true;
                                }
                                let af = AudioFrame::from_payload(&frame.payload)?;
                                push_pcm_s16le_to_ring(&mut prod, &af.data);
                            }
                            _ => {}
                        }
                    }
                }
                Err(err) => {
                    eprintln!("audio connect failed ({err}); retrying in {}ms...", backoff.as_millis());
                    thread::sleep(backoff);
                    backoff = (backoff * 2).min(Duration::from_secs(2));
                }
            }
        }
        Ok(())
    });

    // Keep running until Ctrl+C; simplest is to join forever.
    net_thread.join().unwrap()?;
    Ok(())
}

fn push_pcm_s16le_to_ring(prod: &mut impl Producer<Item = f32>, bytes: &[u8]) {
    let mut i = 0;
    while i + 1 < bytes.len() {
        let s = i16::from_le_bytes([bytes[i], bytes[i + 1]]);
        let f = (s as f32) / 32768.0;
        let _ = prod.try_push(f);
        i += 2;
    }
}

fn fill_f32(out: &mut [f32], cons: &mut impl Consumer<Item = f32>) {
    for s in out.iter_mut() {
        *s = cons.try_pop().unwrap_or(0.0);
    }
}

fn fill_i16(out: &mut [i16], cons: &mut impl Consumer<Item = f32>) {
    for s in out.iter_mut() {
        let f = cons.try_pop().unwrap_or(0.0).clamp(-1.0, 1.0);
        *s = (f * 32767.0) as i16;
    }
}

fn fill_u16(out: &mut [u16], cons: &mut impl Consumer<Item = f32>) {
    for s in out.iter_mut() {
        let f = cons.try_pop().unwrap_or(0.0).clamp(-1.0, 1.0);
        let v = ((f * 0.5 + 0.5) * 65535.0) as i32;
        *s = v.clamp(0, 65535) as u16;
    }
}

fn err_fn(err: cpal::StreamError) {
    eprintln!("audio output error: {err}");
}

