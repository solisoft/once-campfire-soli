#!/usr/bin/env python3
"""A minimal Action Cable client: connect with a cookie, subscribe, print what arrives.

    bench/cable_probe.py HOST:PORT COOKIE_HEADER IDENTIFIER_JSON... [--seconds N] [--send IDENT DATA]
"""
import base64, json, os, socket, struct, sys, time

def frame(text):
    data = text.encode()
    mask = os.urandom(4)
    header = bytes([0x81])
    n = len(data)
    if n < 126:
        header += bytes([0x80 | n])
    elif n < 65536:
        header += bytes([0x80 | 126]) + struct.pack(">H", n)
    else:
        header += bytes([0x80 | 127]) + struct.pack(">Q", n)
    return header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data))

def read_frame(sock, buf):
    while True:
        if len(buf) >= 2:
            n = buf[1] & 0x7F
            off = 2
            if n == 126:
                if len(buf) < 4: pass
                else: n = struct.unpack(">H", buf[2:4])[0]; off = 4
            elif n == 127:
                if len(buf) < 10: pass
                else: n = struct.unpack(">Q", buf[2:10])[0]; off = 10
            if len(buf) >= off + n and not (buf[1] & 0x7F in (126, 127) and off == 2):
                opcode = buf[0] & 0x0F
                payload = buf[off:off + n]
                return opcode, payload, buf[off + n:]
        chunk = sock.recv(65536)
        if not chunk:
            return None, None, buf
        buf += chunk

def main():
    host, cookie = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    seconds = 8
    sends = []
    idents = []
    i = 0
    while i < len(args):
        if args[i] == "--seconds": seconds = float(args[i + 1]); i += 2
        elif args[i] == "--send": sends.append((args[i + 1], args[i + 2])); i += 3
        else: idents.append(args[i]); i += 1
    h, p = host.split(":")
    sock = socket.create_connection((h, int(p)))
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall((f"GET /cable HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: actioncable-v1-json, actioncable-unsupported\r\n"
                  f"Origin: http://{host}\r\nCookie: {cookie}\r\n\r\n").encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += sock.recv(4096)
    head, buf = resp.split(b"\r\n\r\n", 1)
    print(head.decode().split("\r\n")[0])
    for ident in idents:
        sock.sendall(frame(json.dumps({"command": "subscribe", "identifier": ident})))
    time.sleep(0.5)
    for ident, data in sends:
        sock.sendall(frame(json.dumps({"command": "message", "identifier": ident, "data": data})))
    sock.settimeout(0.5)
    end = time.time() + seconds
    while time.time() < end:
        try:
            op, payload, buf = read_frame(sock, buf)
        except socket.timeout:
            continue
        if op is None:
            print("closed"); break
        print(payload.decode(errors="replace")[:300])

main()
