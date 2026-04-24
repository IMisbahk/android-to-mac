use std::process::Command;

use anyhow::{anyhow, Context, Result};

#[derive(Debug, Clone)]
pub struct Device {
    pub serial: String,
    pub description: String,
}

pub fn list_devices() -> Result<Vec<Device>> {
    let out = Command::new("adb")
        .args(["devices", "-l"])
        .output()
        .context("running adb devices -l")?;

    if !out.status.success() {
        return Err(anyhow!(
            "adb devices -l failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }

    let stdout = String::from_utf8_lossy(&out.stdout);
    let mut devices = Vec::new();
    for line in stdout.lines() {
        if line.starts_with("List of devices") || line.trim().is_empty() {
            continue;
        }
        // serial \t state [extras...]
        let mut parts = line.split_whitespace();
        let Some(serial) = parts.next() else { continue };
        let Some(state) = parts.next() else { continue };
        if state != "device" {
            continue;
        }
        devices.push(Device {
            serial: serial.to_string(),
            description: line.to_string(),
        });
    }

    Ok(devices)
}

pub fn forward(serial: &str, host_port: u16, device_port: u16) -> Result<()> {
    let out = Command::new("adb")
        .args(["-s", serial, "forward"])
        .arg(format!("tcp:{host_port}"))
        .arg(format!("tcp:{device_port}"))
        .output()
        .with_context(|| format!("adb forward tcp:{host_port} tcp:{device_port}"))?;

    if !out.status.success() {
        return Err(anyhow!(
            "adb forward failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(())
}

pub fn remove_forward(serial: &str, host_port: u16) -> Result<()> {
    let out = Command::new("adb")
        .args(["-s", serial, "forward", "--remove"])
        .arg(format!("tcp:{host_port}"))
        .output()
        .with_context(|| format!("adb forward --remove tcp:{host_port}"))?;

    if !out.status.success() {
        return Err(anyhow!(
            "adb forward --remove failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(())
}

