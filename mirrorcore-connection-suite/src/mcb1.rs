use std::io::{Read, Write};

use anyhow::Result;
use mirrorcore_protocol::{Frame, Header, StreamCodec};

pub struct Mcb1Stream {
    codec: StreamCodec,
}

impl Default for Mcb1Stream {
    fn default() -> Self {
        Self {
            codec: StreamCodec::default(),
        }
    }
}

impl Mcb1Stream {
    pub fn read_frame<R: Read>(&self, reader: &mut R) -> Result<Frame> {
        Ok(self.codec.read_frame(reader)?)
    }

    pub fn write_frame<W: Write>(&self, writer: &mut W, header: Header, payload: Vec<u8>) -> Result<()> {
        let frame = Frame::new(header, payload)?;
        Ok(self.codec.write_frame(writer, &frame)?)
    }
}

