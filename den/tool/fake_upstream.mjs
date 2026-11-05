// A stand-in for an OpenAI-compatible model server for tool/web_check.mjs:
// streams the user's last message back one character at a time.
//   node tool/fake_upstream.mjs 18080
import http from 'node:http';

const port = Number(process.argv[2] ?? 18080);
http
  .createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/v1/models') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ object: 'list', data: [{ id: 'echo-1', object: 'model' }] }));
      return;
    }
    if (req.method === 'POST' && req.url === '/v1/chat/completions') {
      let body = '';
      req.on('data', (c) => (body += c));
      req.on('end', async () => {
        const request = JSON.parse(body);
        // The gateway must strip its prefix and never forward the device token.
        console.log(`chat model=${request.model} auth=${req.headers.authorization ?? 'none'} messages=${request.messages.length}`);
        const last = request.messages.at(-1)?.content ?? '';
        const reply = [...`你說：「${last}」。這是假的上游模型，用來測試串流。`];
        res.writeHead(200, { 'content-type': 'text/event-stream' });
        for (const ch of reply) {
          res.write(`data: ${JSON.stringify({ choices: [{ index: 0, delta: { content: ch } }] })}\n\n`);
          await new Promise((r) => setTimeout(r, 80));
        }
        res.write(`data: ${JSON.stringify({ choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] })}\n\n`);
        res.write(`data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 42, completion_tokens: reply.length } })}\n\n`);
        res.end('data: [DONE]\n\n');
      });
      return;
    }
    res.writeHead(404).end();
  })
  .listen(port, '127.0.0.1', () => console.log('fake upstream on', port));
