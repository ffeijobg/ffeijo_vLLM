# stub/server.py: serves one model name; set SERVED_MODEL to a wrong value to simulate a bad release
import json, os
from http.server import BaseHTTPRequestHandler, HTTPServer
MODEL = os.getenv("SERVED_MODEL", "lab-model")

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if body.get("model") != MODEL:
            self.send_response(404); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        self.wfile.write(b'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n')
        self.wfile.write(b"data: [DONE]\n\n")

HTTPServer(("", 8000), H).serve_forever()
