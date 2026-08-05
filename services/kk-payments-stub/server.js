const http = require('http');
const { calculateTotal, applyDiscount } = require('./index.js');

const APP_VERSION = process.env.APP_VERSION || require('./package.json').version;
const PORT = parseInt(process.env.PORT || '3000', 10);

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: APP_VERSION, port: PORT }));
    return;
  }

  if (req.url === '/calculate' && req.method === 'POST') {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      try {
        const { items, discountPercent } = JSON.parse(body || '{}');
        let total = calculateTotal(items);
        if (typeof discountPercent === 'number') {
          total = applyDiscount(total, discountPercent);
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ total }));
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  res.writeHead(200);
  res.end('kk-payments-stub ' + APP_VERSION + ' on port ' + PORT + '\n');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('kk-payments-stub ' + APP_VERSION + ' listening on port ' + PORT);
});

module.exports = server;
