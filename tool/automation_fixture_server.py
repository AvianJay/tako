"""Local deterministic model fixture. No credentials or request bodies are logged."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        has_result = any(m.get('role') == 'tool' for m in request.get('messages', []))
        delta = {'content': 'Automation fixture result'} if has_result else {
            'tool_calls': [{'index': 0, 'id': 'fixture-status', 'type': 'function',
                            'function': {'name': 'get_device_status', 'arguments': '{}'}}]
        }
        packet = {'id': 'fixture', 'choices': [{'index': 0, 'delta': delta,
                  'finish_reason': 'stop' if has_result else 'tool_calls'}]}
        body = ('data: ' + json.dumps(packet) + '\n\ndata: [DONE]\n\n').encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 18080), Handler).serve_forever()
