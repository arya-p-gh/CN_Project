from http.server import BaseHTTPRequestHandler, HTTPServer
import json


class BackendBHandler(BaseHTTPRequestHandler):

    def send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend", "B")
        self.send_header("Cache-Control", "max-age=60")
        self.send_header("ETag", '"backend-b-v1"')
        self.end_headers()

        self.wfile.write(body)

    def do_GET(self):

        if self.headers.get("If-None-Match") == '"backend-b-v1"':
            self.send_response(304)
            self.send_header("ETag", '"backend-b-v1"')
            self.send_header("Cache-Control", "max-age=60")
            self.end_headers()
            return

        if self.path == "/":
            self.send_json({
                "backend": "B",
                "status": "ok"
            })

        elif self.path == "/api/status":
            self.send_json({
                "backend": "B",
                "status": "ok"
            })

        else:
            self.send_json({
                "backend": "B",
                "status": "not_found"
            }, 404)


server = HTTPServer(("0.0.0.0", 3002), BackendBHandler)

print("Backend B running on 10.7.10.56:3002")

server.serve_forever()
