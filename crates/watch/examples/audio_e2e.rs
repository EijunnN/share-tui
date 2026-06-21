//! Throwaway end-to-end check that the relay forwards host voice to viewers.
//! Run a relay on 127.0.0.1:4455, then: cargo run --example audio_e2e -p watch

use bytes::Bytes;
use futures_util::{SinkExt, StreamExt};
use protocol::{
    decode, encode, HostHello, HostToRelay, RelayToHost, RelayToWatch, WatchHello, WatchToRelay,
    PROTOCOL_VERSION,
};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

type Ws = WebSocketStream<MaybeTlsStream<TcpStream>>;

fn b<T: serde::Serialize>(m: &T) -> Message {
    Message::Binary(Bytes::from(encode(m)))
}

#[tokio::main]
async fn main() {
    let base = "ws://127.0.0.1:4455";

    let (mut host, _) = tokio_tungstenite::connect_async(format!("{base}/host"))
        .await
        .expect("host connect");
    host.send(b(&HostToRelay::Hello(HostHello {
        name: "host".into(),
        shell: "test".into(),
        public: true,
        cols: 80,
        rows: 24,
        auth_key: None,
        chat: false,
        version: PROTOCOL_VERSION.into(),
    })))
    .await
    .unwrap();
    let code = loop {
        match host.next().await {
            Some(Ok(Message::Binary(x))) => {
                if let Ok(RelayToHost::Welcome { code, .. }) = decode::<RelayToHost>(&x[..]) {
                    break code;
                }
            }
            _ => panic!("no host welcome"),
        }
    };

    // Watcher joins.
    let mut ws: Ws = {
        let (mut w, _) = tokio_tungstenite::connect_async(format!("{base}/watch"))
            .await
            .expect("watch connect");
        w.send(b(&WatchToRelay::Hello(WatchHello {
            version: PROTOCOL_VERSION.into(),
            name: None,
            cols: 0,
            rows: 0,
        })))
        .await
        .unwrap();
        w.next().await; // Welcome
        w.send(b(&WatchToRelay::Join { target: code.clone() }))
            .await
            .unwrap();
        loop {
            match w.next().await {
                Some(Ok(Message::Binary(x))) => {
                    if matches!(decode::<RelayToWatch>(&x[..]), Ok(RelayToWatch::Joined { .. })) {
                        break;
                    }
                }
                _ => panic!("no joined"),
            }
        }
        w
    };

    // Host transmits one voice frame.
    let payload: Vec<u8> = audio::encode_frame(&[10, -20, 30, -40, 12345]);
    host.send(b(&HostToRelay::Audio(payload.clone()))).await.unwrap();

    let got = tokio::time::timeout(std::time::Duration::from_secs(5), async {
        loop {
            if let Some(Ok(Message::Binary(x))) = ws.next().await
                && let Ok(RelayToWatch::Audio(bytes)) = decode::<RelayToWatch>(&x[..])
            {
                return bytes;
            }
        }
    })
    .await;

    match got {
        Ok(bytes) => {
            let ok = bytes == payload && audio::decode_frame(&bytes) == [10, -20, 30, -40, 12345];
            println!("received {} bytes, decoded ok: {}", bytes.len(), ok);
            println!("{}", if ok { "PASS" } else { "FAIL" });
            if !ok {
                std::process::exit(1);
            }
        }
        Err(_) => {
            println!("FAIL: timed out waiting for audio");
            std::process::exit(1);
        }
    }
}
