#!/usr/bin/env python3
"""MiningSim co-op relay.

Lets a player host without port forwarding. The host's game keeps one UDP "tunnel" open to
the relay's control port; the relay gives that host its own join port, and friends connect
to <relay>:<join port> as if it were the host. Packets are passed through untouched (they're
DTLS-encrypted end to end, so the relay can't read them).

Only builds that share the co-op secret can register as a host: the relay sends a random
challenge and the host must answer with HMAC-SHA256(secret, challenge + b"miningsim-relay").

Control port messages (host <-> relay):
  host  -> b"MSR1H"                     hello, asks for a challenge
  relay -> b"MSR1C" + 16 random bytes   the challenge
  host  -> b"MSR1A" + 32-byte HMAC      the answer
  relay -> b"MSR1O" + port (u16 LE) + public address (utf-8)   registered
  host  -> b"MSR1K"  /  relay -> b"MSR1K"   keepalive (every few seconds)
  either-> b"D" + joiner id (u32 LE) + payload   game traffic for/from one joiner
  relay -> b"X" + joiner id (u32 LE)    that joiner went quiet; drop its link
  relay -> b"MSR1F"                     no free room / not registered (start over)

Run:  python3 relay.py --secret-file /etc/miningsim-relay/secret
"""

import argparse
import hashlib
import hmac
import os
import selectors
import socket
import struct
import sys
import time
import urllib.request

CONTROL_PORT = 24690
JOIN_PORTS = range(24691, 24695)  # one per hosted game
HOST_TIMEOUT = 30.0  # a room closes this long after its host goes quiet
JOINER_TIMEOUT = 60.0
CHALLENGE_TIMEOUT = 10.0
MAX_JOINERS = 8
MAX_PACKET = 2048
IP_REFRESH = 1800.0
TAG = b"miningsim-relay"


def log(*args):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *args, flush=True)


class Room:
    def __init__(self, port, sock, host_addr):
        self.port = port
        self.sock = sock  # the join socket friends send to
        self.host_addr = host_addr
        self.host_seen = time.monotonic()
        self.joiners = {}  # addr -> [id, last_seen]
        self.by_id = {}  # id -> addr
        self.next_id = 1


class Relay:
    def __init__(self, secret, public_host, bind="0.0.0.0"):
        self.bind = bind
        self.secret = secret
        self.public_host = public_host
        self.public_fixed = bool(public_host)
        self.ip_checked = 0.0
        self.sel = selectors.DefaultSelector()
        self.control = self._udp(CONTROL_PORT)
        self.sel.register(self.control, selectors.EVENT_READ, None)
        self.free = list(JOIN_PORTS)
        self.rooms = {}  # join port -> Room
        self.host_room = {}  # host addr -> Room
        self.challenges = {}  # addr -> (nonce, time)

    def _udp(self, port):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind((self.bind, port))
        s.setblocking(False)
        return s

    def refresh_ip(self):
        if self.public_fixed or time.monotonic() - self.ip_checked < IP_REFRESH:
            return
        self.ip_checked = time.monotonic()
        try:
            ip = urllib.request.urlopen("https://api.ipify.org", timeout=5).read().decode().strip()
            if ip and ip != self.public_host:
                log("public address is", ip)
                self.public_host = ip
        except OSError as e:
            log("couldn't look up public address:", e)

    def run(self):
        log("relay up: control", CONTROL_PORT, "join", JOIN_PORTS.start, "-", JOIN_PORTS.stop - 1)
        while True:
            self.refresh_ip()
            for key, _ in self.sel.select(timeout=1.0):
                sock = key.fileobj
                for _ in range(256):  # drain, but keep the loop fair
                    try:
                        data, addr = sock.recvfrom(MAX_PACKET)
                    except BlockingIOError:
                        break
                    except OSError:
                        break
                    if sock is self.control:
                        self.on_control(data, addr)
                    else:
                        self.on_join(key.data, data, addr)
            self.expire()

    # --- Hosts -------------------------------------------------------------------------

    def on_control(self, data, addr):
        room = self.host_room.get(addr)
        if data[:1] == b"D" and len(data) >= 5:
            if room is None:
                return
            room.host_seen = time.monotonic()
            jid = struct.unpack_from("<I", data, 1)[0]
            jaddr = room.by_id.get(jid)
            if jaddr:
                room.sock.sendto(data[5:], jaddr)
        elif data == b"MSR1K":
            if room:
                room.host_seen = time.monotonic()
                self.control.sendto(b"MSR1K", addr)
            else:
                self.control.sendto(b"MSR1F", addr)
        elif data == b"MSR1H":
            nonce = os.urandom(16)
            self.challenges[addr] = (nonce, time.monotonic())
            self.control.sendto(b"MSR1C" + nonce, addr)
        elif data[:5] == b"MSR1A" and len(data) == 5 + 32:
            nonce, t = self.challenges.pop(addr, (None, 0.0))
            if nonce is None or time.monotonic() - t > CHALLENGE_TIMEOUT:
                return
            want = hmac.new(self.secret, nonce + TAG, hashlib.sha256).digest()
            if not hmac.compare_digest(want, data[5:]):
                log("bad answer from", addr)
                return
            if room is None:
                if not self.free:
                    log("no free room for", addr)
                    self.control.sendto(b"MSR1F", addr)
                    return
                port = self.free.pop(0)
                sock = self._udp(port)
                room = Room(port, sock, addr)
                self.sel.register(sock, selectors.EVENT_READ, room)
                self.rooms[port] = room
                self.host_room[addr] = room
                log("room", port, "opened for", addr)
            room.host_seen = time.monotonic()
            self.control.sendto(b"MSR1O" + struct.pack("<H", room.port) + self.public_host.encode(), addr)

    # --- Joiners -----------------------------------------------------------------------

    def on_join(self, room, data, addr):
        now = time.monotonic()
        j = room.joiners.get(addr)
        if j is None:
            if len(room.joiners) >= MAX_JOINERS:
                return
            j = [room.next_id, now]
            room.next_id += 1
            room.joiners[addr] = j
            room.by_id[j[0]] = addr
            log("room", room.port, "joiner", j[0], "from", addr)
        j[1] = now
        self.control.sendto(b"D" + struct.pack("<I", j[0]) + data, room.host_addr)

    def expire(self):
        now = time.monotonic()
        for addr, (_, t) in list(self.challenges.items()):
            if now - t > CHALLENGE_TIMEOUT:
                del self.challenges[addr]
        for room in list(self.rooms.values()):
            if now - room.host_seen > HOST_TIMEOUT:
                self.close(room)
                continue
            for addr, (jid, seen) in list(room.joiners.items()):
                if now - seen > JOINER_TIMEOUT:
                    del room.joiners[addr]
                    room.by_id.pop(jid, None)
                    self.control.sendto(b"X" + struct.pack("<I", jid), room.host_addr)

    def close(self, room):
        log("room", room.port, "closed")
        self.sel.unregister(room.sock)
        room.sock.close()
        self.rooms.pop(room.port, None)
        self.host_room.pop(room.host_addr, None)
        self.free.append(room.port)
        self.free.sort()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--secret-file", required=True, help="file holding the co-op SECRET (hex)")
    ap.add_argument("--public-host", default="", help="address friends type (default: look it up)")
    ap.add_argument("--bind", default="0.0.0.0", help="listen address (127.0.0.1 for testing)")
    args = ap.parse_args()
    secret = bytes.fromhex(open(args.secret_file).read().strip())
    if len(secret) < 16:
        sys.exit("secret too short")
    Relay(secret, args.public_host, args.bind).run()


if __name__ == "__main__":
    main()
