"""A local HTTP proxy that adds a round-trip time, for benchmarking the app as someone off the server's network.

    python tool/perf/latency_proxy.py --rtt 80

Prints `PORT <n>` once it listens on 127.0.0.1, and runs until its stdin closes (the driver holds the pipe,
so the proxy goes when the driver does).

A connection starts with `TUNNEL host:port\r\n\r\n` (what the app sends in bench mode, see
lib/perf_bench/bench_http.dart: no answer, the client starts TLS right after it) or a standard
`CONNECT host:port` (answered with 200). Either way TLS stays end to end: the proxy only moves bytes. Each direction's
data is delivered rtt/2 after it arrived, in order, so a request/response exchange on an open connection costs
one extra rtt, and a new connection pays one rtt for its setup (the TCP handshake) before the tunnel opens, plus
the rtts of the TLS handshake through the delayed tunnel - like a real link. Plain http requests (absolute-form)
are forwarded to the host of the connection's first request the same way.

Threads, not asyncio: asyncio's timers on Windows follow the 15.6 ms tick, time.sleep is accurate to ~1 ms.
"""
import argparse
import collections
import socket
import sys
import threading
import time


def _nodelay(sock):
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except OSError:
        pass


class DelayLine:
    """Delivers what `src` sends to `dst`, each chunk `delay` seconds after it arrived."""

    def __init__(self, src, dst, delay, first=None, on_done=None):
        self.src, self.dst, self.delay = src, dst, delay
        self.queue = collections.deque()
        self.cond = threading.Condition()
        self.on_done = on_done
        if first:
            self.queue.append((time.perf_counter() + delay, first))

    def start(self):
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._write, daemon=True).start()

    def _read(self):
        while True:
            try:
                data = self.src.recv(1 << 16)
            except OSError:
                data = b""
            with self.cond:
                self.queue.append((time.perf_counter() + self.delay, data))
                self.cond.notify()
            if not data:
                return

    def _write(self):
        try:
            while True:
                with self.cond:
                    while not self.queue:
                        self.cond.wait()
                    due, data = self.queue.popleft()
                wait = due - time.perf_counter()
                if wait > 0:
                    time.sleep(wait)
                if not data:
                    try:
                        self.dst.shutdown(socket.SHUT_WR)
                    except OSError:
                        pass
                    return
                self.dst.sendall(data)
        except OSError:
            pass
        finally:
            if self.on_done:
                self.on_done()


def read_head(sock):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(1 << 16)
        if not chunk:
            return None, b""
        data += chunk
        if len(data) > 1 << 20:
            return None, b""
    head, rest = data.split(b"\r\n\r\n", 1)
    return head.decode("latin-1"), rest


def handle(client, rtt):
    half = rtt / 2
    upstream = None
    try:
        _nodelay(client)
        head, rest = read_head(client)
        if head is None:
            client.close()
            return
        method, target = head.split("\r\n", 1)[0].split(" ", 2)[:2]
        if method.upper() in ("CONNECT", "TUNNEL"):
            host, _, port = target.rpartition(":")
            port = int(port or 443)
        else:
            # absolute-form: http://host[:port]/path
            without = target.split("://", 1)[-1]
            hostport = without.split("/", 1)[0]
            host, _, port = hostport.partition(":")
            port = int(port or 80)
        # The connection's setup: one round trip before anything can flow.
        started = time.perf_counter()
        upstream = socket.create_connection((host.strip("[]"), port), timeout=30)
        upstream.settimeout(None)
        _nodelay(upstream)
        left = rtt - (time.perf_counter() - started)
        if left > 0:
            time.sleep(left)
        if method.upper() == "CONNECT":
            client.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
            first = rest
        elif method.upper() == "TUNNEL":
            first = rest
        else:
            first = head.encode("latin-1") + b"\r\n\r\n" + rest
        done = {"n": 0}
        lock = threading.Lock()

        def finished():
            with lock:
                done["n"] += 1
                if done["n"] == 2:
                    for s in (client, upstream):
                        try:
                            s.close()
                        except OSError:
                            pass

        DelayLine(client, upstream, half, first=first or None, on_done=finished).start()
        DelayLine(upstream, client, half, on_done=finished).start()
    except (OSError, ValueError):
        for s in (client, upstream):
            if s is not None:
                try:
                    s.close()
                except OSError:
                    pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rtt", type=float, required=True, help="round-trip time to add, in ms")
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    rtt = args.rtt / 1000.0
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(("127.0.0.1", args.port))
    server.listen(256)
    print(f"PORT {server.getsockname()[1]}", flush=True)

    def accept():
        while True:
            try:
                client, _ = server.accept()
            except OSError:
                return
            threading.Thread(target=handle, args=(client, rtt), daemon=True).start()

    threading.Thread(target=accept, daemon=True).start()
    # Until the driver closes our stdin (or dies).
    try:
        sys.stdin.buffer.read()
    except (OSError, ValueError):
        pass


if __name__ == "__main__":
    main()
