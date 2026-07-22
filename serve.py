import http.server
import socketserver
import os

PORT = 8080
os.chdir(os.path.join(os.path.dirname(__file__), 'build', 'web'))

class SPAHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        path = self.translate_path(self.path)
        if not os.path.exists(path):
            self.path = '/index.html'
        return super().do_GET()
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()
    def log_message(self, format, *args):
        pass

with socketserver.TCPServer(('', PORT), SPAHandler) as httpd:
    print(f'Serving on http://localhost:{PORT}')
    httpd.serve_forever()
