const http = require("http");
const os = require("os");

const PORT = process.env.PORT || 3000;
const INSTANCE = process.env.INSTANCE_NAME || os.hostname();

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  // Health check — Nginx ya monitoring tool isko hit karega
  if (url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    return res.end("OK");
  }

  // Slow endpoint — latency debugging practice ke liye
  // /slow?ms=3000 hit karoge to 3 second lagega
  if (url.pathname === "/slow") {
    const delay = parseInt(url.searchParams.get("ms") || "3000", 10);
    return setTimeout(
      () => {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ instance: INSTANCE, delayed: delay }));
      },
      Math.min(delay, 30000),
    );
  }

  // Crash endpoint — 502 page test karne ke liye
  if (url.pathname === "/crash") {
    res.writeHead(500);
    res.end("Simulated crash");
    return process.exit(1);
  }

  // Bada JSON response — gzip test karne ke liye
  if (url.pathname === "/big") {
    const bigData = Array.from({ length: 500 }, (_, i) => ({
      id: i,
      name: `Product number ${i}`,
      description:
        "Ye ek lamba description hai jo gzip compression test karne ke liye repeat ho raha hai.",
    }));
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ instance: INSTANCE, items: bigData }));
  }

  // Default route
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(
    JSON.stringify(
      {
        message: "Hello from backend",
        instance: INSTANCE,
        hostname: os.hostname(),
        path: url.pathname,
        clientIp: req.headers["x-real-ip"] || "not-set",
        forwardedProto: req.headers["x-forwarded-proto"] || "not-set",
        timestamp: new Date().toISOString(),
      },
      null,
      2,
    ),
  );
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[${INSTANCE}] Backend listening on port ${PORT}`);
});

// Graceful shutdown — docker stop pe clean exit
process.on("SIGTERM", () => {
  console.log(`[${INSTANCE}] SIGTERM received, shutting down`);
  server.close(() => process.exit(0));
});
