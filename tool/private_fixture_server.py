"""One-shot loopback credential bridge for an Android emulator integration test.

No credential is written to an APK or logged. The server exits after one fetch.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread, Timer
import secrets

parser = argparse.ArgumentParser()
parser.add_argument('--file', required=True)
parser.add_argument('--port', type=int, default=18746)
args = parser.parse_args()
payload = Path(args.file).read_bytes()
ticket = secrets.token_urlsafe(32)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass
    def do_GET(self):
        if self.path != '/' + ticket:
            self.send_error(403)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        Thread(target=self.server.shutdown, daemon=True).start()

server = HTTPServer(('127.0.0.1', args.port), Handler)
expiry = Timer(180, server.shutdown)
expiry.daemon = True
expiry.start()
print('EMULATOR_FIXTURE_URL=http://10.0.2.2:' + str(args.port) + '/' + ticket, flush=True)
try:
    server.serve_forever()
finally:
    server.server_close()
    expiry.cancel()
