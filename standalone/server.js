const http = require("http");
const fs = require("fs");
const path = require("path");
const { WebSocketServer } = require("ws");

const port = Number(process.env.PORT || 8090);
const rooms = new Map();
const rootDir = __dirname;
const parentDir = path.resolve(rootDir, "..");

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".json": "application/json; charset=utf-8",
};

function randomRoomId() {
  return Math.floor(1000 + Math.random() * 9000).toString();
}

function getRoom(roomId) {
  return rooms.get(roomId) ?? null;
}

function send(socket, payload) {
  if (socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(payload));
  }
}

function cleanupRoom(roomId) {
  const room = getRoom(roomId);
  if (!room) {
    return;
  }
  if (!room.host && !room.guest) {
    rooms.delete(roomId);
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, port }));
    return;
  }

  let filePath;
  if (url.pathname === "/" || url.pathname === "/index.html") {
    filePath = path.join(rootDir, "index.html");
  } else if (url.pathname === "/styles.css") {
    filePath = path.join(rootDir, "styles.css");
  } else if (url.pathname === "/game.js") {
    filePath = path.join(rootDir, "game.js");
  } else if (url.pathname === "/art/title_zork.png") {
    filePath = path.join(parentDir, "art", "title_zork.png");
  } else {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found");
    return;
  }

  fs.readFile(filePath, (error, data) => {
    if (error) {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("Not found");
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, { "Content-Type": mimeTypes[ext] || "application/octet-stream" });
    res.end(data);
  });
});

const wss = new WebSocketServer({ server });

wss.on("connection", (socket) => {
  socket.meta = { role: null, roomId: null };

  socket.on("message", (raw) => {
    let message;
    try {
      message = JSON.parse(String(raw));
    } catch {
      send(socket, { type: "error", message: "Invalid JSON." });
      return;
    }

    if (message.type === "host_room") {
      let roomId = randomRoomId();
      while (rooms.has(roomId)) {
        roomId = randomRoomId();
      }
      rooms.set(roomId, { host: socket, guest: null });
      socket.meta = { role: "host", roomId };
      send(socket, { type: "room_created", roomId, role: "host" });
      return;
    }

    if (message.type === "join_room") {
      const roomId = String(message.roomId || "").trim();
      const room = getRoom(roomId);
      if (!room || !room.host) {
        send(socket, { type: "error", message: "Room not found." });
        return;
      }
      if (room.guest) {
        send(socket, { type: "error", message: "Room is full." });
        return;
      }
      room.guest = socket;
      socket.meta = { role: "guest", roomId };
      send(socket, { type: "room_joined", roomId, role: "guest" });
      send(room.host, { type: "guest_joined", roomId });
      return;
    }

    const room = getRoom(socket.meta.roomId);
    if (!room) {
      send(socket, { type: "error", message: "No active room." });
      return;
    }

    if (message.type === "snapshot" && socket.meta.role === "host" && room.guest) {
      send(room.guest, { type: "snapshot", state: message.state });
      return;
    }

    if (message.type === "input" && socket.meta.role === "guest" && room.host) {
      send(room.host, { type: "input", input: message.input });
      return;
    }

    if (message.type === "action" && room.host) {
      if (socket.meta.role === "guest") {
        send(room.host, { type: "action", action: message.action });
      } else if (room.guest) {
        send(room.guest, { type: "action", action: message.action });
      }
      return;
    }
  });

  socket.on("close", () => {
    const { roomId, role } = socket.meta;
    const room = getRoom(roomId);
    if (!room) {
      return;
    }
    if (role === "host") {
      if (room.guest) {
        send(room.guest, { type: "peer_left" });
        room.guest.close();
      }
      rooms.delete(roomId);
      return;
    }
    if (role === "guest") {
      room.guest = null;
      if (room.host) {
        send(room.host, { type: "peer_left" });
      }
      cleanupRoom(roomId);
    }
  });
});

server.listen(port, () => {
  console.log(`Zork PvP relay listening on ws://localhost:${port}`);
});
