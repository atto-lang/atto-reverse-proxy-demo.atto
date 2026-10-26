//! Dependency-free, loopback-only HTTP/1.1 connection-close benchmark.
//! A closed-loop baseline; not a saturation/open-loop or TLS benchmark.
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Barrier};
use std::time::{Duration, Instant};

const LIMIT: usize = 1024 * 1024;
const INGRESS: &[u8] = b"Upstream forwarding unavailable in this runtime";
#[cfg(test)]
const TEST_NONCE: &str = "0123456789abcdef0123456789abcdef";

fn nonce(s: &str) -> Result<&str, String> {
    if s.len() != 32 || !s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
        return Err("origin nonce must be exactly 32 lowercase hex characters".into());
    }
    Ok(s)
}

fn address(s: &str) -> Result<SocketAddr, String> {
    let a: SocketAddr = s.parse().map_err(|_| "expected numeric loopback IP:port")?;
    if !a.ip().is_loopback() {
        return Err("only loopback destinations allowed".into());
    }
    Ok(a)
}
fn number(s: &str, min: usize, max: usize) -> Result<usize, String> {
    let n = s.parse::<usize>().map_err(|_| "invalid integer")?;
    if n < min || n > max {
        return Err(format!("integer outside {min}..{max}"));
    }
    Ok(n)
}
fn expected(profile: &str, size: usize) -> Result<(u16, Vec<u8>, String), String> {
    match profile {
        "ingress" if size == 0 => Ok((501, INGRESS.to_vec(), "/ingress".into())),
        "forward" if size <= 65536 => Ok((200, vec![b'x'; size], format!("/bytes/{size}"))),
        _ => Err("profile must be ingress (size 0) or forward (size 0..65536)".into()),
    }
}
fn origin_request_size(wire: &[u8]) -> Result<usize, String> {
    let end = wire
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or("incomplete request headers")?;
    if end > 16384 {
        return Err("request header budget".into());
    }
    let head =
        std::str::from_utf8(&wire[..end]).map_err(|_| "non UTF-8 fixture request headers")?;
    let mut lines = head.split("\r\n");
    let request_line = lines.next().ok_or("missing request line")?;
    let mut parts = request_line.split(' ');
    let method = parts.next().ok_or("missing request method")?;
    let target = parts.next().ok_or("missing request target")?;
    let version = parts.next().ok_or("missing request version")?;
    if parts.next().is_some() || method != "GET" || version != "HTTP/1.1" {
        return Err("unexpected request line".into());
    }
    let size = target
        .strip_prefix("/bytes/")
        .and_then(|s| number(s, 0, 65536).ok())
        .ok_or("unexpected request target")?;
    let mut host_seen = false;
    for line in lines {
        if line.starts_with(' ') || line.starts_with('\t') {
            return Err("folded request header".into());
        }
        let (key, value) = line.split_once(':').ok_or("malformed request header")?;
        if key.eq_ignore_ascii_case("host") {
            if host_seen || value.trim() != "bench.example.test" {
                return Err("duplicate or unexpected Host".into());
            }
            host_seen = true;
        }
    }
    if !host_seen {
        return Err("missing Host".into());
    }
    Ok(size)
}
// This fixture deliberately supports a bounded Content-Length/connection-close
// response only. Reject unsupported framing rather than timing partial bodies.
fn verify_with_nonce(
    bytes: &[u8],
    profile: &str,
    size: usize,
    origin_nonce: &str,
) -> Result<(), String> {
    let end = bytes
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or("missing header terminator")?;
    if end > 16384 {
        return Err("response header budget".into());
    }
    let head = std::str::from_utf8(&bytes[..end]).map_err(|_| "non UTF-8 fixture headers")?;
    let mut lines = head.split("\r\n");
    let status: Vec<_> = lines.next().ok_or("missing status")?.split(' ').collect();
    let (code, body, _) = expected(profile, size)?;
    if status.len() < 2
        || !matches!(status[0], "HTTP/1.0" | "HTTP/1.1")
        || status[1] != code.to_string()
    {
        return Err("unexpected status (501 is not forwarding success)".into());
    }
    let mut length = None;
    let mut marker = None;
    for line in lines {
        if line.starts_with(' ') || line.starts_with('\t') {
            return Err("folded header".into());
        }
        let (key, value) = line.split_once(':').ok_or("malformed header")?;
        let key = key.to_ascii_lowercase();
        let value = value.trim();
        if key == "transfer-encoding" || key == "content-encoding" {
            return Err("unsupported fixture encoding".into());
        }
        if key == "content-length" {
            if length.is_some() || value.is_empty() || !value.bytes().all(|c| c.is_ascii_digit()) {
                return Err("duplicate/invalid Content-Length".into());
            }
            length = Some(
                value
                    .parse::<usize>()
                    .map_err(|_| "Content-Length overflow")?,
            );
        }
        if key == "x-bench-origin" {
            if marker.is_some() {
                return Err("duplicate origin marker".into());
            }
            marker = Some(value);
        }
    }
    if length != Some(body.len()) || bytes[end + 4..] != body {
        return Err("fixture body mismatch".into());
    }
    if profile == "forward" && marker != Some(origin_nonce) {
        return Err("missing or stale origin nonce".into());
    }
    if profile == "ingress" && marker.is_some() {
        return Err("ingress unexpectedly reached origin".into());
    }
    Ok(())
}
#[cfg(test)]
fn verify(bytes: &[u8], profile: &str, size: usize) -> Result<(), String> {
    verify_with_nonce(bytes, profile, size, TEST_NONCE)
}
fn request(
    addr: SocketAddr,
    profile: &str,
    size: usize,
    origin_nonce: &str,
) -> Result<u64, String> {
    let (_, _, path) = expected(profile, size)?;
    let start = Instant::now();
    let mut s =
        TcpStream::connect_timeout(&addr, Duration::from_secs(2)).map_err(|e| e.to_string())?;
    s.set_read_timeout(Some(Duration::from_secs(2)))
        .map_err(|e| e.to_string())?;
    s.set_write_timeout(Some(Duration::from_secs(2)))
        .map_err(|e| e.to_string())?;
    let wire =
        format!("GET {path} HTTP/1.1\r\nHost: bench.example.test\r\nConnection: close\r\n\r\n");
    s.write_all(wire.as_bytes()).map_err(|e| e.to_string())?;
    let mut response = Vec::new();
    // Total deadline, as well as per-read timeout, bounds trickling peers.
    let mut buf = [0u8; 8192];
    loop {
        if start.elapsed() > Duration::from_secs(5) {
            return Err("total response deadline".into());
        }
        let n = s.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        if response.len() + n > LIMIT {
            return Err("response byte budget".into());
        }
        response.extend_from_slice(&buf[..n]);
    }
    // Time to complete EOF-delimited response, excluding correctness parsing.
    let micros = start.elapsed().as_micros().min(u64::MAX as u128) as u64;
    verify_with_nonce(&response, profile, size, origin_nonce)?;
    Ok(micros)
}
fn percentile(sorted: &[u64], p: usize) -> u64 {
    sorted[(sorted.len() * p).div_ceil(100).saturating_sub(1)]
}
fn run(args: &[String]) -> Result<(), String> {
    if args.len() != 7 {
        return Err(
            "run IP:PORT ingress|forward BYTES REQUESTS CONCURRENCY WARMUP ORIGIN_NONCE".into(),
        );
    }
    let addr = address(&args[0])?;
    let profile = &args[1];
    let size = number(&args[2], 0, 65536)?;
    expected(profile, size)?;
    let total = number(&args[3], 1, 1_000_000)?;
    let concurrency = number(&args[4], 1, 256)?;
    if concurrency > total {
        return Err("concurrency exceeds requests".into());
    }
    let warmup = number(&args[5], 0, 10000)?;
    let origin_nonce = nonce(&args[6])?.to_string();
    // Preflight/warmup must finish successfully before any measured request.
    request(addr, profile, size, &origin_nonce).map_err(|e| format!("preflight: {e}"))?;
    for _ in 0..warmup {
        request(addr, profile, size, &origin_nonce).map_err(|e| format!("warmup: {e}"))?;
    }
    let next = Arc::new(AtomicUsize::new(0));
    let barrier = Arc::new(Barrier::new(concurrency + 1));
    let mut workers = Vec::new();
    for _ in 0..concurrency {
        let next = next.clone();
        let barrier = barrier.clone();
        let profile = profile.clone();
        let origin_nonce = origin_nonce.clone();
        workers.push(std::thread::spawn(move || {
            let mut samples = Vec::new();
            let mut errors = 0usize;
            barrier.wait();
            loop {
                if next.fetch_add(1, Ordering::Relaxed) >= total {
                    break;
                }
                match request(addr, &profile, size, &origin_nonce) {
                    Ok(t) => samples.push(t),
                    Err(_) => errors += 1,
                }
            }
            (samples, errors)
        }));
    }
    let start = Instant::now();
    barrier.wait();
    let mut samples = Vec::with_capacity(total);
    let mut errors = 0;
    for worker in workers {
        let (mut local, failed) = worker.join().map_err(|_| "worker panic")?;
        samples.append(&mut local);
        errors += failed;
    }
    let seconds = start.elapsed().as_secs_f64();
    samples.sort_unstable();
    if errors != 0 || samples.len() != total {
        println!("{{\"schema\":1,\"status\":\"INVALID\",\"completed\":{},\"errors\":{errors},\"attempted\":{total}}}", samples.len());
        return Err("measured request failed correctness/transport; no comparable metrics".into());
    }
    println!("{{\"schema\":1,\"status\":\"PASS\",\"profile\":\"{profile}\",\"connection\":\"close\",\"load\":\"closed-loop\",\"bytes\":{size},\"requests\":{total},\"concurrency\":{concurrency},\"warmup\":{warmup},\"seconds\":{seconds:.6},\"requests_per_second\":{:.3},\"p50_us\":{},\"p95_us\":{},\"p99_us\":{},\"max_us\":{},\"errors\":0}}", total as f64 / seconds, percentile(&samples,50), percentile(&samples,95), percentile(&samples,99), samples.last().unwrap());
    Ok(())
}
fn origin(addr: SocketAddr, origin_nonce: String) -> Result<(), String> {
    let listener = TcpListener::bind(addr).map_err(|e| e.to_string())?;
    // Bounded fixture workers with a bounded channel; never one thread/request.
    let (tx, rx) = std::sync::mpsc::sync_channel::<TcpStream>(256);
    let rx = Arc::new(std::sync::Mutex::new(rx));
    for _ in 0..16 {
        let rx = rx.clone();
        let origin_nonce = origin_nonce.clone();
        std::thread::spawn(move || loop {
            let stream = rx.lock().unwrap().recv();
            let Ok(mut s) = stream else {
                break;
            };
            let _ = s.set_read_timeout(Some(Duration::from_secs(2)));
            let _ = s.set_write_timeout(Some(Duration::from_secs(2)));
            let mut wire = Vec::new();
            let mut buf = [0u8; 1024];
            while wire.len() < 16384 && !wire.windows(4).any(|w| w == b"\r\n\r\n") {
                match s.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => wire.extend_from_slice(&buf[..n]),
                }
            }
            match origin_request_size(&wire) {
                Ok(size) => {
                    let head = format!("HTTP/1.1 200 OK\r\nContent-Length: {size}\r\nContent-Type: application/octet-stream\r\nX-Bench-Origin: {origin_nonce}\r\nConnection: close\r\n\r\n");
                    let _ = s.write_all(head.as_bytes());
                    let _ = s.write_all(&vec![b'x'; size]);
                }
                Err(_) => {
                    let _ = s.write_all(
                        b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                    );
                }
            }
        });
    }
    for stream in listener.incoming() {
        tx.send(stream.map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("run") => run(&args[1..]),
        Some("origin") if args.len() == 3 => address(&args[1]).and_then(|addr| {
            let origin_nonce = nonce(&args[2])?.to_string();
            origin(addr, origin_nonce)
        }),
        _ => Err("usage: ores-proxy-bench origin IP:PORT ORIGIN_NONCE | run IP:PORT ingress|forward BYTES REQUESTS CONCURRENCY WARMUP ORIGIN_NONCE".into()),
    };
    if let Err(e) = result {
        eprintln!("benchmark rejected: {e}");
        std::process::exit(1);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn response(status: u16, extra: &str, body: &[u8]) -> Vec<u8> {
        let mut b = format!(
            "HTTP/1.1 {status} Fixture\r\nContent-Length: {}\r\n{extra}\r\n",
            body.len()
        )
        .into_bytes();
        b.extend_from_slice(body);
        b
    }
    #[test]
    fn origin_request_requires_complete_expected_semantics() {
        let valid =
            b"GET /bytes/3 HTTP/1.1\r\nHost: bench.example.test\r\nConnection: close\r\n\r\n";
        assert_eq!(origin_request_size(valid).unwrap(), 3);

        for invalid in [
            b"GET /bytes/3 HTTP/1.1\r\nHost: bench.example.test\r\n".as_slice(),
            b"POST /bytes/3 HTTP/1.1\r\nHost: bench.example.test\r\n\r\n",
            b"GET /bytes/3 HTTP/1.0\r\nHost: bench.example.test\r\n\r\n",
            b"GET /other HTTP/1.1\r\nHost: bench.example.test\r\n\r\n",
            b"GET /bytes/3 HTTP/1.1\r\n\r\n",
            b"GET /bytes/3 HTTP/1.1\r\nHost: wrong.example.test\r\n\r\n",
            b"GET /bytes/3 HTTP/1.1\r\nHost: bench.example.test\r\nHost: bench.example.test\r\n\r\n",
            b"GET /bytes/3 HTTP/1.1\r\nHost: bench.example.test\r\n folded: x\r\n\r\n",
            b"GET /bytes/3 HTTP/1.1\r\nHost bench.example.test\r\n\r\n",
        ] {
            assert!(origin_request_size(invalid).is_err());
        }
    }

    #[test]
    fn origin_request_rejects_invalid_encoding_and_header_budget() {
        let mut invalid_utf8 =
            b"GET /bytes/3 HTTP/1.1\r\nHost: bench.example.test\r\nX-Bad: ".to_vec();
        invalid_utf8.push(255);
        invalid_utf8.extend_from_slice(b"\r\n\r\n");
        assert!(origin_request_size(&invalid_utf8).is_err());

        let mut oversized =
            b"GET /bytes/3 HTTP/1.1\r\nHost: bench.example.test\r\nX-Fill: ".to_vec();
        oversized.extend(std::iter::repeat_n(b'a', 16384));
        oversized.extend_from_slice(b"\r\n\r\n");
        assert!(origin_request_size(&oversized).is_err());
    }

    #[test]
    fn exact_origin_body_and_marker() {
        assert!(verify(
            &response(200, &format!("X-Bench-Origin: {TEST_NONCE}\r\n"), b"xxx"),
            "forward",
            3
        )
        .is_ok());
        assert!(verify(&response(200, "", b"xxx"), "forward", 3).is_err());
        assert!(verify(
            &response(200, &format!("X-Bench-Origin: {TEST_NONCE}\r\n"), b"bad"),
            "forward",
            3
        )
        .is_err());
    }
    #[test]
    fn stale_origin_marker_is_not_forwarding_proof() {
        let stale = response(200, "X-Bench-Origin: fixture-v1\r\n", b"xxx");
        assert!(verify_with_nonce(&stale, "forward", 3, TEST_NONCE).is_err());
        let fresh = response(200, &format!("X-Bench-Origin: {TEST_NONCE}\r\n"), b"xxx");
        assert!(verify_with_nonce(&fresh, "forward", 3, TEST_NONCE).is_ok());
        assert!(nonce(TEST_NONCE).is_ok());
        assert!(nonce("fixture-v1").is_err());
        assert!(nonce("ABCDEF0123456789ABCDEF0123456789").is_err());
    }

    #[test]
    fn failure_is_not_forwarding() {
        assert!(verify(&response(501, "", INGRESS), "ingress", 0).is_ok());
        assert!(verify(&response(501, "", INGRESS), "forward", 0).is_err());
        assert!(verify(
            &response(200, &format!("X-Bench-Origin: {TEST_NONCE}\r\n"), b""),
            "ingress",
            0
        )
        .is_err());
    }
    #[test]
    fn ambiguous_or_unsupported_framing() {
        for h in [
            "Content-Length: 3\r\n",
            "Transfer-Encoding: chunked\r\n",
            "Content-Encoding: gzip\r\n",
            "X-Bench-Origin: fixture-v1\r\n",
            " folded: x\r\n",
        ] {
            assert!(verify(
                &response(200, &format!("X-Bench-Origin: {TEST_NONCE}\r\n{h}"), b"xxx"),
                "forward",
                3
            )
            .is_err());
        }
    }
    #[test]
    fn truncated_extra_and_no_headers() {
        for b in [
            b"HTTP/1.1 200 OK".as_slice(),
            b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nX-Bench-Origin: fixture-v1\r\n\r\nxx",
            b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nX-Bench-Origin: fixture-v1\r\n\r\nxxxx",
        ] {
            assert!(verify(b, "forward", 3).is_err());
        }
    }
    #[test]
    fn preflight_rejects_501_before_measurement() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut b = [0; 1024];
            let _ = s.read(&mut b);
            s.write_all(&response(501, "", INGRESS)).unwrap();
        });
        let result = run(&[
            addr.to_string(),
            "forward".into(),
            "0".into(),
            "1".into(),
            "1".into(),
            "0".into(),
            TEST_NONCE.into(),
        ]);
        assert!(result.unwrap_err().contains("preflight"));
        server.join().unwrap();
    }
    #[test]
    fn bounds_and_percentiles() {
        assert!(address("192.0.2.1:80").is_err());
        assert!(address("example.test:80").is_err());
        assert!(address("127.0.0.1:9090").is_ok());
        assert!(number("0", 1, 256).is_err());
        assert!(number("257", 1, 256).is_err());
        assert_eq!(percentile(&[1, 2, 3, 4], 50), 2);
        assert_eq!(percentile(&[1, 2, 3, 4], 99), 4);
    }
    #[test]
    fn network_request_checks_fixture() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut b = [0; 1024];
            let _ = s.read(&mut b);
            s.write_all(&response(
                200,
                &format!("X-Bench-Origin: {TEST_NONCE}\r\n"),
                b"xxx",
            ))
            .unwrap();
        });
        assert!(request(addr, "forward", 3, TEST_NONCE).is_ok());
        server.join().unwrap();
    }
}
