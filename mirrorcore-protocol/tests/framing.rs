use mirrorcore_protocol::{enums::MsgType, Header, StreamCodec};

#[test]
fn framing_test_file_smoke() {
    let _ = StreamCodec::default();
    let _ = Header::new(MsgType::Ping as u8, 0, 1, 123, 0);
}

