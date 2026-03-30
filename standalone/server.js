const http = require("http");
const fs = require("fs");
const path = require("path");
const { WebSocketServer } = require("ws");

const port = Number(process.env.PORT || 8090);
const rooms = new Map();
let nextClientId = 1;
const matchState = {
  active: false,
  hostClientId: null,
};
const rootDir = __dirname;
const parentDir = path.resolve(rootDir, "..");
const lobbyColors = ["red", "blue", "green", "yellow", "orange", "purple", "pink", "teal", "white", "brown"];
const lobbySlots = Array.from({ length: 8 }, () => ({
  type: "empty",
  colorId: null,
  handle: "",
  clientId: null,
}));

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

function sanitizeHandle(value) {
  return String(value || "").replace(/\s+/g, " ").trim().slice(0, 18);
}

function claimLobbySlot(socket) {
  if (Number.isInteger(socket.meta.lobbySlotIndex)) {
    return socket.meta.lobbySlotIndex;
  }
  const index = lobbySlots.findIndex((slot) => slot.type === "empty");
  if (index === -1) {
    socket.meta.lobbySlotIndex = null;
    return null;
  }
  lobbySlots[index] = {
    ...lobbySlots[index],
    type: "player",
    colorId: lobbySlots[index].colorId ?? null,
    handle: "",
    clientId: socket.meta.clientId,
  };
  socket.meta.lobbySlotIndex = index;
  return index;
}

function releaseLobbySlot(socket) {
  if (!Number.isInteger(socket.meta.lobbySlotIndex)) {
    return;
  }
  const index = socket.meta.lobbySlotIndex;
  lobbySlots[index] = {
    ...lobbySlots[index],
    type: "empty",
    colorId: null,
    handle: "",
    clientId: null,
  };
  socket.meta.lobbySlotIndex = null;
}

function buildLobbyPayload(socket) {
  return {
    type: "lobby_sync",
    clientId: socket.meta.clientId,
    localSlotIndex: Number.isInteger(socket.meta.lobbySlotIndex) ? socket.meta.lobbySlotIndex : null,
    slots: lobbySlots,
    matchActive: matchState.active,
    matchHostClientId: matchState.hostClientId,
  };
}

function broadcastLobby() {
  for (const client of wss.clients) {
    if (client.readyState === client.OPEN) {
      send(client, buildLobbyPayload(client));
    }
  }
}

function getClaimedPlayers() {
  return lobbySlots
    .map((slot, index) => ({ slot, index }))
    .filter(({ slot }) => slot.type === "player" && slot.clientId);
}

function getCurrentHostClientId() {
  return getClaimedPlayers()[0]?.slot.clientId ?? null;
}

function findSocketByClientId(clientId) {
  for (const client of wss.clients) {
    if (client.readyState === client.OPEN && client.meta?.clientId === clientId) {
      return client;
    }
  }
  return null;
}

function broadcastMatch(payload, excludeClientId = null) {
  for (const client of wss.clients) {
    if (client.readyState !== client.OPEN) {
      continue;
    }
    if (excludeClientId && client.meta?.clientId === excludeClientId) {
      continue;
    }
    send(client, payload);
  }
}

function endMatch(reason = "Match ended.") {
  if (!matchState.active) {
    return;
  }
  matchState.active = false;
  matchState.hostClientId = null;
  broadcastMatch({ type: "match_end", reason });
  broadcastLobby();
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
  socket.meta = { role: null, roomId: null, clientId: `client-${nextClientId++}`, lobbySlotIndex: null };

  socket.on("message", (raw) => {
    let message;
    try {
      message = JSON.parse(String(raw));
    } catch {
      send(socket, { type: "error", message: "Invalid JSON." });
      return;
    }

    if (message.type === "lobby_join") {
      claimLobbySlot(socket);
      send(socket, buildLobbyPayload(socket));
      broadcastLobby();
      return;
    }

    if (message.type === "lobby_handle") {
      if (!Number.isInteger(socket.meta.lobbySlotIndex)) {
        claimLobbySlot(socket);
      }
      if (!Number.isInteger(socket.meta.lobbySlotIndex)) {
        send(socket, { type: "lobby_error", message: "Lobby is full." });
        return;
      }
      lobbySlots[socket.meta.lobbySlotIndex].handle = sanitizeHandle(message.handle);
      broadcastLobby();
      return;
    }

    if (message.type === "lobby_color") {
      if (!Number.isInteger(socket.meta.lobbySlotIndex)) {
        claimLobbySlot(socket);
      }
      if (!Number.isInteger(socket.meta.lobbySlotIndex)) {
        send(socket, { type: "lobby_error", message: "Lobby is full." });
        return;
      }
      const colorId = String(message.colorId || "").trim();
      if (!lobbyColors.includes(colorId)) {
        send(socket, { type: "lobby_error", message: "Unknown color." });
        return;
      }
      const taken = lobbySlots.some((slot, index) => (
        index !== socket.meta.lobbySlotIndex &&
        slot.type === "player" &&
        slot.colorId === colorId
      ));
      if (taken) {
        send(socket, { type: "lobby_error", message: "Color already taken." });
        return;
      }
      lobbySlots[socket.meta.lobbySlotIndex].colorId = colorId;
      broadcastLobby();
      return;
    }

    if (message.type === "lobby_start") {
      if (!Number.isInteger(socket.meta.lobbySlotIndex)) {
        send(socket, { type: "lobby_error", message: "Claim a lobby slot first." });
        return;
      }
      if (matchState.active) {
        send(socket, { type: "lobby_error", message: "A match is already running." });
        return;
      }
      const claimedPlayers = getClaimedPlayers();
      if (!claimedPlayers.length) {
        send(socket, { type: "lobby_error", message: "No players are in the lobby." });
        return;
      }
      matchState.active = true;
      matchState.hostClientId = getCurrentHostClientId();
      broadcastMatch({
        type: "match_start",
        hostClientId: matchState.hostClientId,
        slots: lobbySlots,
      });
      broadcastLobby();
      return;
    }

    if (message.type === "lobby_set_slot") {
      const hostClientId = getCurrentHostClientId();
      if (!hostClientId || socket.meta.clientId !== hostClientId) {
        send(socket, { type: "lobby_error", message: "Only the temporary host can edit empty slots." });
        return;
      }
      if (matchState.active) {
        send(socket, { type: "lobby_error", message: "You cannot change slots during a match." });
        return;
      }
      const slotIndex = Number(message.slotIndex);
      const nextType = message.slotType === "npc" ? "npc" : "empty";
      if (!Number.isInteger(slotIndex) || slotIndex < 0 || slotIndex >= lobbySlots.length) {
        send(socket, { type: "lobby_error", message: "Unknown lobby slot." });
        return;
      }
      const slot = lobbySlots[slotIndex];
      if (slot.clientId) {
        send(socket, { type: "lobby_error", message: "That slot is already claimed by a player." });
        return;
      }
      lobbySlots[slotIndex] = {
        ...slot,
        type: nextType,
        handle: nextType === "npc" ? `NPC ${slotIndex + 1}` : "",
        clientId: null,
      };
      broadcastLobby();
      return;
    }

    if (message.type === "match_end") {
      endMatch("Back to lobby");
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
      if (matchState.active) {
        const team = Number.isInteger(socket.meta.lobbySlotIndex) ? socket.meta.lobbySlotIndex + 1 : null;
        const hostSocket = findSocketByClientId(matchState.hostClientId);
        if (message.type === "snapshot" && socket.meta.clientId === matchState.hostClientId) {
          broadcastMatch({ type: "snapshot", state: message.state }, matchState.hostClientId);
          return;
        }
        if (message.type === "input" && hostSocket && team != null && socket.meta.clientId !== matchState.hostClientId) {
          send(hostSocket, { type: "input", team, input: message.input });
          return;
        }
        if (message.type === "action" && hostSocket && team != null && socket.meta.clientId !== matchState.hostClientId) {
          send(hostSocket, { type: "action", action: { ...message.action, team } });
          return;
        }
      }
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
    const closingTeam = Number.isInteger(socket.meta.lobbySlotIndex) ? socket.meta.lobbySlotIndex + 1 : null;
    const wasHost = socket.meta.clientId === matchState.hostClientId;
    releaseLobbySlot(socket);
    if (matchState.active) {
      if (wasHost) {
        endMatch("Host left the match.");
      } else if (closingTeam != null) {
        const hostSocket = findSocketByClientId(matchState.hostClientId);
        if (hostSocket) {
          send(hostSocket, { type: "peer_left", team: closingTeam });
        }
        broadcastMatch({ type: "player_left", team: closingTeam });
        broadcastLobby();
      } else {
        broadcastLobby();
      }
    } else {
      broadcastLobby();
    }

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
