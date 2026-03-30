const canvas = document.getElementById("game");
const ctx = canvas.getContext("2d");

const titleScreen = document.getElementById("titleScreen");
const hud = document.getElementById("hud");
const quickFightButton = document.getElementById("quickFightButton");
const handleInput = document.getElementById("handleInput");
const resetFightButton = document.getElementById("resetFightButton");
const lobbySlots = document.getElementById("lobbySlots");
const titleLobbyStatus = document.getElementById("titleLobbyStatus");
const playerStats = document.getElementById("playerStats");
const statusText = document.getElementById("statusText");
const targetList = document.getElementById("targetList");
const castleState = document.getElementById("castleState");
const powerplantState = document.getElementById("powerplantState");
const spawnWarriorButton = document.getElementById("spawnWarriorButton");
const castleUpgradeButton = document.getElementById("castleUpgradeButton");
const powerUpgradeButton = document.getElementById("powerUpgradeButton");
const powerReserveButton = document.getElementById("powerReserveButton");

const CASTLE_DRAW = {
  bodyWidth: 180,
  bodyHeight: 120,
  bodyTop: -110,
  towerWidth: 54,
  towerHeight: 72,
  sideTowerOffsetX: 88,
  sideTowerTop: -142,
  centerTowerWidth: 58,
  centerTowerHeight: 92,
  centerTowerTop: -160,
};

const WORLD = {
  width: 28000,
  height: 22000,
};

const ARENA = {
  x: WORLD.width / 2,
  y: WORLD.height / 2,
  radius: 9200,
};

const BASE_LAYOUT = {
  playerRadius: ARENA.radius - 2500,
  castleFromPlayer: 920,
  shieldFromCastle: 1340,
  powerFromCastle: 1340,
  shieldArcRadius: 360,
  shieldArcThickness: 28,
  dormantMinionOffset: 250,
};

const MAX_ARMS = 8;
const LOBBY_COLORS = [
  { id: "red", label: "Red", value: "#ff5c5c" },
  { id: "blue", label: "Blue", value: "#63b3ff" },
  { id: "green", label: "Green", value: "#67e380" },
  { id: "yellow", label: "Yellow", value: "#ffe66b" },
  { id: "orange", label: "Orange", value: "#ff9f4a" },
  { id: "purple", label: "Purple", value: "#b985ff" },
  { id: "pink", label: "Pink", value: "#ff8ec7" },
  { id: "teal", label: "Teal", value: "#54e1d6" },
  { id: "white", label: "White", value: "#f2f6ff" },
  { id: "brown", label: "Brown", value: "#b98a68" },
];

function createEmptyLobbyState() {
  return Array.from({ length: 8 }, (_, index) => ({
    type: "empty",
    colorId: LOBBY_COLORS[index % LOBBY_COLORS.length].id,
    handle: "",
    clientId: null,
  }));
}

const STATE = {
  mode: "title",
  keys: new Set(),
  game: null,
  mouseWorld: { x: WORLD.width / 2, y: WORLD.height / 2 },
  selectedTargetTeam: null,
  lobby: createEmptyLobbyState(),
  touchMove: { active: false, pointerId: null, originX: 0, originY: 0, currentX: 0, currentY: 0 },
};

const COLORS = {
  bg: "#030406",
  arenaGlow: "rgba(70, 136, 255, 0.15)",
  orb: "#8cf881",
  crystal: "#3ad86f",
  crystalCore: "#b9ffd1",
  player: "#f2f6ff",
  enemy: "#ffd6a8",
  crack: "#6d1010",
  castle: "#f6f7fb",
  castleEnemy: "#ffdcae",
  uiDanger: "#ff7a7a",
  minion: "#f6f8ff",
  minionEnemy: "#ffc488",
  damage: "#ff7d7d",
  healing: "#a3ffc8",
};

let audioContext = null;
let audioUnlocked = false;
let basslineStep = 0;
let nextBasslineTime = 0;
let network = {
  mode: "pve",
  socket: null,
  clientId: null,
  localSlotIndex: null,
  lobbyConnected: false,
  matchActive: false,
  matchHostClientId: null,
  roomId: "",
  localTeam: 1,
  peerConnected: false,
  lastStatus: "",
  remoteInputs: {},
  lastSnapshotSentAt: 0,
};

function getAudioContext() {
  if (!audioContext) {
    const AudioCtor = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtor) {
      return null;
    }
    audioContext = new AudioCtor();
  }
  return audioContext;
}

function unlockAudio() {
  const audio = getAudioContext();
  if (!audio) {
    return;
  }
  if (audio.state === "suspended") {
    audio.resume();
  }
  audioUnlocked = true;
  if (nextBasslineTime <= 0) {
    nextBasslineTime = audio.currentTime + 0.08;
  }
}

function playSound(steps, options = {}) {
  const audio = getAudioContext();
  if (!audio || !audioUnlocked) {
    return;
  }

  const start = options.startTime ?? (audio.currentTime + (options.delay ?? 0));
  const gainNode = audio.createGain();
  gainNode.gain.setValueAtTime(options.volume ?? 0.08, start);
  gainNode.connect(audio.destination);

  let cursor = start;
  for (const step of steps) {
    const duration = step.duration ?? 0.08;
    const osc = audio.createOscillator();
    const oscGain = audio.createGain();
    osc.type = step.type ?? options.type ?? "square";
    osc.frequency.setValueAtTime(step.frequency, cursor);
    if (step.frequencyEnd) {
      osc.frequency.exponentialRampToValueAtTime(step.frequencyEnd, cursor + duration);
    }
    const peak = step.volume ?? 1;
    oscGain.gain.setValueAtTime(0.0001, cursor);
    oscGain.gain.exponentialRampToValueAtTime(peak, cursor + 0.01);
    oscGain.gain.exponentialRampToValueAtTime(0.0001, cursor + duration);
    osc.connect(oscGain);
    oscGain.connect(gainNode);
    osc.start(cursor);
    osc.stop(cursor + duration + 0.02);
    cursor += duration + (step.gap ?? 0.01);
  }

  gainNode.gain.exponentialRampToValueAtTime(0.0001, cursor + 0.04);
}

function updateBassline() {
  const audio = getAudioContext();
  if (!audio || !audioUnlocked || STATE.mode !== "round") {
    return;
  }
  if (nextBasslineTime < audio.currentTime) {
    nextBasslineTime = audio.currentTime + 0.05;
  }

  const pattern = [65.41, 82.41, 98.0, 82.41, 130.81, 98.0, 82.41, 98.0];
  while (nextBasslineTime < audio.currentTime + 0.35) {
    const frequency = pattern[basslineStep % pattern.length];
    playSound(
      [
        { frequency, duration: 0.18, type: "triangle", volume: 1.1 },
        { frequency: frequency * 2, duration: 0.12, type: "sine", volume: 0.24, gap: 0 },
      ],
      { volume: 0.05, startTime: nextBasslineTime },
    );
    nextBasslineTime += 0.22;
    basslineStep += 1;
  }
}

function playCastleBuildSound() {
  playSound(
    [
      { frequency: 294, duration: 0.08, type: "triangle" },
      { frequency: 392, duration: 0.1, type: "triangle" },
      { frequency: 587, duration: 0.18, type: "square", volume: 1.2 },
    ],
    { volume: 0.09 },
  );
}

function playCrystalHitSound() {
  playSound(
    [
      { frequency: 980, frequencyEnd: 760, duration: 0.05, type: "triangle" },
      { frequency: 1320, frequencyEnd: 980, duration: 0.04, type: "sine", volume: 0.5 },
    ],
    { volume: 0.045 },
  );
}

function playArmPickupSound() {
  playSound(
    [
      { frequency: 440, duration: 0.06, type: "square" },
      { frequency: 554, duration: 0.06, type: "square" },
      { frequency: 659, duration: 0.14, type: "triangle", volume: 1.2 },
    ],
    { volume: 0.07 },
  );
}

function playSwordClashSound() {
  playSound(
    [
      { frequency: 1180, frequencyEnd: 820, duration: 0.035, type: "square" },
      { frequency: 1760, frequencyEnd: 1220, duration: 0.04, type: "triangle", volume: 0.55 },
    ],
    { volume: 0.05 },
  );
}

function playMinionSpawnSound() {
  playSound(
    [
      { frequency: 520, duration: 0.05, type: "square" },
      { frequency: 620, duration: 0.05, type: "square" },
      { frequency: 480, duration: 0.11, type: "triangle", volume: 1.15 },
    ],
    { volume: 0.06 },
  );
}

function playErrorSound() {
  playSound(
    [
      { frequency: 240, duration: 0.055, type: "square" },
      { frequency: 180, duration: 0.09, type: "square", volume: 0.9 },
    ],
    { volume: 0.07 },
  );
}

function connectSocket() {
  if (network.socket && (network.socket.readyState === WebSocket.OPEN || network.socket.readyState === WebSocket.CONNECTING)) {
    return network.socket;
  }
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const socket = new WebSocket(`${protocol}//${window.location.host}`);
  network.socket = socket;

  socket.addEventListener("open", () => {
    network.lobbyConnected = true;
    network.lastStatus = "Connected to shared lobby";
    sendSocket({ type: "lobby_join" });
    updateTitleLobbyUi();
  });

  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.type === "lobby_sync") {
      applyLobbySync(message.slots, message.clientId, message.localSlotIndex);
      network.matchActive = Boolean(message.matchActive);
      network.matchHostClientId = message.matchHostClientId ?? null;
      network.lastStatus = message.localSlotIndex == null ? "Lobby full" : `Lobby slot ${message.localSlotIndex + 1}`;
      updateTitleLobbyUi();
    } else if (message.type === "lobby_error") {
      network.lastStatus = message.message;
      playErrorSound();
      updateTitleLobbyUi();
    } else if (message.type === "match_start") {
      network.matchActive = true;
      network.matchHostClientId = message.hostClientId ?? null;
      startNetworkRound(message.hostClientId === network.clientId ? "host" : "client");
      network.lastStatus = message.hostClientId === network.clientId ? "Hosting shared match" : "Joined shared match";
    } else if (message.type === "match_end") {
      network.matchActive = false;
      network.matchHostClientId = null;
      network.lastStatus = message.reason || "Match ended";
      if (STATE.mode === "round") {
        STATE.game = null;
        STATE.mode = "title";
        titleScreen.classList.remove("hidden");
        hud.classList.add("hidden");
      }
      updateTitleLobbyUi();
    } else if (message.type === "input" && network.mode === "match-host") {
      network.remoteInputs[message.team] = message.input;
    } else if (message.type === "snapshot" && network.mode === "match-client") {
      STATE.game = message.state;
    } else if (message.type === "action" && network.mode === "match-host") {
      handleRemoteAction(message.action);
    } else if (message.type === "player_left") {
      network.lastStatus = `Player ${message.team} left`;
    } else if (message.type === "peer_left") {
      network.peerConnected = false;
      network.lastStatus = message.team ? `Player ${message.team} disconnected` : "Peer disconnected";
      if (message.team != null) {
        delete network.remoteInputs[message.team];
      }
    } else if (message.type === "error") {
      network.lastStatus = message.message;
      playErrorSound();
    }
  });

  socket.addEventListener("close", () => {
    if (network.socket === socket) {
      network.socket = null;
    }
    network.lobbyConnected = false;
    if (network.mode === "title") {
      network.lastStatus = "Shared lobby disconnected";
      updateTitleLobbyUi();
      window.setTimeout(() => {
        if (STATE.mode === "title" && !network.socket) {
          connectSocket();
        }
      }, 1200);
    }
    if (network.mode !== "pve") {
      network.peerConnected = false;
      network.lastStatus = "Disconnected";
    }
  });

  return socket;
}

function sendSocket(payload) {
  if (network.socket && network.socket.readyState === WebSocket.OPEN) {
    network.socket.send(JSON.stringify(payload));
  }
}

function collectNetworkInput() {
  const touchDx = STATE.touchMove.currentX - STATE.touchMove.originX;
  const touchDy = STATE.touchMove.currentY - STATE.touchMove.originY;
  return {
    left: STATE.keys.has("KeyA") || (STATE.touchMove.active && touchDx < -14),
    right: STATE.keys.has("KeyD") || (STATE.touchMove.active && touchDx > 14),
    up: STATE.keys.has("KeyW") || (STATE.touchMove.active && touchDy < -14),
    down: STATE.keys.has("KeyS") || (STATE.touchMove.active && touchDy > 14),
    dash: STATE.keys.has("ShiftLeft"),
    deposit: STATE.keys.has("KeyE"),
  };
}

function startNetworkRound(role) {
  STATE.game = spawnGame("shared-match");
  network.mode = role === "host" ? "match-host" : "match-client";
  network.remoteInputs = {};
  network.localTeam = (network.localSlotIndex ?? 0) + 1;
  STATE.mode = "round";
  basslineStep = 0;
  const audio = getAudioContext();
  nextBasslineTime = audio ? audio.currentTime + 0.08 : 0;
  titleScreen.classList.add("hidden");
  hud.classList.remove("hidden");
}

function serializeGameState(game) {
  return {
    camera: game.camera,
    players: game.players.map((player) => ({
      id: player.id,
      team: player.team,
      nickname: player.nickname,
      color: player.color,
      x: player.x,
      y: player.y,
      rotation: player.rotation,
      radius: player.radius,
      bodyHp: player.bodyHp,
      maxBodyHp: player.maxBodyHp,
      energy: player.energy,
      maxEnergy: player.maxEnergy,
      arms: player.arms,
      armLength: player.armLength,
      armWidth: player.armWidth,
      armFlashTimer: player.armFlashTimer,
      bodyFlashTimer: player.bodyFlashTimer,
      dead: player.dead,
    })),
    orbs: game.orbs,
    crystals: game.crystals,
    pads: game.pads,
    minions: game.minions,
    floatingText: game.floatingText,
    roundTime: game.roundTime,
    winner: game.winner,
  };
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function distance(a, b) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.hypot(dx, dy);
}

function normalize(x, y) {
  const len = Math.hypot(x, y);
  if (!len) {
    return { x: 0, y: 0 };
  }
  return { x: x / len, y: y / len };
}

function circleCollision(a, ar, b, br) {
  return distance(a, b) <= ar + br;
}

function segmentPointDistance(ax, ay, bx, by, px, py) {
  const abx = bx - ax;
  const aby = by - ay;
  const apx = px - ax;
  const apy = py - ay;
  const abLenSq = abx * abx + aby * aby || 1;
  const t = clamp((apx * abx + apy * aby) / abLenSq, 0, 1);
  const cx = ax + abx * t;
  const cy = ay + aby * t;
  return Math.hypot(px - cx, py - cy);
}

function segmentCollision(segA, radiusA, segB, radiusB) {
  const checks = [
    segmentPointDistance(segA.x1, segA.y1, segA.x2, segA.y2, segB.x1, segB.y1),
    segmentPointDistance(segA.x1, segA.y1, segA.x2, segA.y2, segB.x2, segB.y2),
    segmentPointDistance(segB.x1, segB.y1, segB.x2, segB.y2, segA.x1, segA.y1),
    segmentPointDistance(segB.x1, segB.y1, segB.x2, segB.y2, segA.x2, segA.y2),
  ];
  return Math.min(...checks) <= radiusA + radiusB;
}

function buildSpawnPoints(count = 8) {
  const points = [];
  const radius = BASE_LAYOUT.playerRadius;
  for (let i = 0; i < count; i += 1) {
    const angle = -Math.PI + (Math.PI * 2 * i) / count;
    const outwardX = Math.cos(angle);
    const outwardY = Math.sin(angle);
    const inwardX = -outwardX;
    const inwardY = -outwardY;
    points.push({
      x: ARENA.x + outwardX * radius,
      y: ARENA.y + outwardY * radius,
      angle,
      outwardX,
      outwardY,
      inwardX,
      inwardY,
      tangentX: -inwardY,
      tangentY: inwardX,
    });
  }
  return points;
}

function getColorById(colorId) {
  return LOBBY_COLORS.find((color) => color.id === colorId) ?? LOBBY_COLORS[0];
}

function sanitizeHandle(value) {
  return String(value || "").replace(/\s+/g, " ").trim().slice(0, 18);
}

function getLocalLobbySlot() {
  if (network.localSlotIndex == null) {
    return null;
  }
  return STATE.lobby[network.localSlotIndex] ?? null;
}

function getClaimedLobbyPlayers() {
  return STATE.lobby
    .map((slot, index) => ({ slot, index }))
    .filter(({ slot }) => slot.type === "player" && slot.clientId);
}

function isTemporaryLobbyHost() {
  return getClaimedLobbyPlayers()[0]?.slot.clientId === network.clientId;
}

function syncHandleInputFromLobby() {
  if (!handleInput) {
    return;
  }
  const localSlot = getLocalLobbySlot();
  handleInput.disabled = false;
  if (document.activeElement !== handleInput) {
    handleInput.value = localSlot?.handle ?? "";
  }
}

function applyLobbySync(slots, localClientId, localSlotIndex = null) {
  STATE.lobby = Array.isArray(slots)
    ? slots.map((slot, index) => ({
        type: slot?.type === "player" ? "player" : (slot?.type === "npc" ? "npc" : "empty"),
        colorId: getColorById(slot?.colorId ?? LOBBY_COLORS[index % LOBBY_COLORS.length].id).id,
        handle: sanitizeHandle(slot?.handle),
        clientId: slot?.clientId ?? null,
      }))
    : createEmptyLobbyState();

  network.clientId = localClientId ?? network.clientId;
  network.localSlotIndex = Number.isInteger(localSlotIndex) ? localSlotIndex : STATE.lobby.findIndex((slot) => slot.clientId === network.clientId);
  network.localTeam = network.localSlotIndex != null && network.localSlotIndex >= 0 ? network.localSlotIndex + 1 : 1;
  renderLobbySlots();
  syncHandleInputFromLobby();
  updateTitleLobbyUi();
}

function sendLobbyHandle() {
  const handle = sanitizeHandle(handleInput?.value);
  const localSlot = getLocalLobbySlot();
  if (localSlot) {
    localSlot.handle = handle;
  }
  if (network.socket && network.socket.readyState === WebSocket.OPEN && network.lobbyConnected) {
    sendSocket({ type: "lobby_handle", handle });
  }
}

function sendLobbyColor(colorId) {
  const localSlot = getLocalLobbySlot();
  if (!localSlot) {
    return;
  }
  localSlot.colorId = colorId;
  renderLobbySlots();
  if (network.socket && network.socket.readyState === WebSocket.OPEN && network.lobbyConnected) {
    sendSocket({ type: "lobby_color", colorId });
  }
}

function sendLobbySlotType(slotIndex, slotType) {
  if (!isTemporaryLobbyHost()) {
    playErrorSound();
    return;
  }
  if (network.socket && network.socket.readyState === WebSocket.OPEN && network.lobbyConnected) {
    sendSocket({ type: "lobby_set_slot", slotIndex, slotType });
  }
}

function updateTitleLobbyUi() {
  const localSlot = getLocalLobbySlot();
  const activePlayers = STATE.lobby.filter((slot) => slot.type === "player").length;
  const activeNpcs = STATE.lobby.filter((slot) => slot.type === "npc").length;
  const connected = network.socket && network.socket.readyState === WebSocket.OPEN && network.lobbyConnected;
  let message = "Connecting to shared lobby...";
  if (!connected) {
    message = "Reconnecting to shared lobby...";
  } else if (localSlot) {
    message = `Shared lobby live. You are in slot ${network.localSlotIndex + 1}. ${activePlayers} players, ${activeNpcs} NPCs.`;
  } else if (activePlayers >= STATE.lobby.length) {
    message = "Shared lobby is full right now.";
  } else {
    message = `Shared lobby live. Waiting to claim a slot... ${activePlayers} players, ${activeNpcs} NPCs.`;
  }
  if (connected && network.matchActive) {
    message = localSlot
      ? `Match live. Slot ${network.localSlotIndex + 1} is in the round.`
      : "Match live. Waiting for the next lobby reset.";
  }
  if (titleLobbyStatus) {
    titleLobbyStatus.textContent = message;
  }
  if (quickFightButton) {
    quickFightButton.disabled = !localSlot || !connected || network.matchActive;
  }
}

function spawnGame(mode = "pve") {
  const activeSlots = STATE.lobby
    .map((slot, index) => ({ slot, index }))
    .filter(({ slot }) => slot.type !== "empty");
  const spawnPoints = buildSpawnPoints(Math.max(activeSlots.length, 1));
  const players = [];
  const pads = [];

  if (mode === "pve" || mode === "shared-match") {
    const localSlotIndex = network.localSlotIndex != null && network.localSlotIndex >= 0 ? network.localSlotIndex : 0;
    for (let i = 0; i < activeSlots.length; i += 1) {
      const { slot, index: slotIndex } = activeSlots[i];
      const point = spawnPoints[i];
      const controlType = slot.type === "npc"
        ? "idle"
        : (
            mode === "pve"
              ? (slotIndex === localSlotIndex ? "local" : "idle")
              : (slotIndex === localSlotIndex ? "local" : "remote")
          );
      const color = getColorById(slot.colorId).value;
      const fallbackName = slot.type === "npc" ? `NPC ${slotIndex + 1}` : `Player ${slotIndex + 1}`;
      players.push(createPlayer({
        id: `player-${slotIndex + 1}`,
        team: slotIndex + 1,
        x: point.x,
        y: point.y,
        isHuman: controlType === "local",
        controlType,
        nickname: sanitizeHandle(slot.handle) || fallbackName,
        color,
      }));
      pads.push(createCastlePad(slotIndex + 1, point));
    }
  } else {
    const p1 = spawnPoints[0];
    const p2 = spawnPoints[4];
    players.push(createPlayer({
      id: "player-1",
      team: 1,
      x: p1.x,
      y: p1.y,
      isHuman: true,
      controlType: "local",
      nickname: "Player 1",
      color: getColorById(STATE.lobby[0]?.colorId ?? "white").value,
    }));
    players.push(createPlayer({
      id: "player-2",
      team: 2,
      x: p2.x,
      y: p2.y,
      isHuman: true,
      controlType: "remote",
      nickname: "Player 2",
      color: getColorById(STATE.lobby[1]?.colorId ?? "red").value,
    }));
    pads.push(createCastlePad(1, p1));
    pads.push(createCastlePad(2, p2));
  }

  const cameraPlayer = players.find((player) => player.team === network.localTeam) ?? players[0];

  return {
    camera: { x: cameraPlayer?.x ?? ARENA.x, y: cameraPlayer?.y ?? ARENA.y, zoom: 1 },
    players,
    orbs: buildOrbs(),
    crystals: buildCrystals(),
    pads,
    minions: [],
    particles: [],
    floatingText: [],
    roundTime: 0,
    tickTimer: 0,
    winner: null,
    npcSpawnCooldown: 0,
  };
}

function createPlayer({ id, team, x, y, isHuman, nickname, color = COLORS.player, controlType = isHuman ? "local" : "ai" }) {
  return {
    type: "player",
    id,
    team,
    nickname,
    color,
    isHuman,
    controlType,
    x,
    y,
    vx: 0,
    vy: 0,
    rotation: isHuman ? 0 : Math.PI,
    radius: 90,
    bodyHp: 100,
    maxBodyHp: 100,
    energy: 20,
    maxEnergy: 20,
    arms: [
      { hp: 40, maxHp: 40, crack: false },
      { hp: 40, maxHp: 40, crack: false },
    ],
    armLength: 230,
    armWidth: 18,
    armDamageCooldown: new Map(),
    remoteInput: { left: false, right: false, up: false, down: false, dash: false, deposit: false },
    bodyHitCooldown: 0,
    armFlashTimer: 0,
    bodyFlashTimer: 0,
    dashCooldown: 0,
    dashTimer: 0,
    dead: false,
    moveSpeed: isHuman ? 1600 : 1200,
    spinSpeed: isHuman ? 2.3 : 1.9,
  };
}

function createCastlePad(team, spawnPoint) {
  const x = spawnPoint.x + spawnPoint.inwardX * BASE_LAYOUT.castleFromPlayer;
  const y = spawnPoint.y + spawnPoint.inwardY * BASE_LAYOUT.castleFromPlayer;
  return {
    type: "pad",
    team,
    x,
    y,
    inwardX: spawnPoint.inwardX,
    inwardY: spawnPoint.inwardY,
    tangentX: spawnPoint.tangentX,
    tangentY: spawnPoint.tangentY,
    facingAngle: Math.atan2(spawnPoint.inwardY, spawnPoint.inwardX),
    size: 170,
    storedEnergy: 0,
    requiredEnergy: 20,
    shieldStoredEnergy: 0,
    shieldRequiredEnergy: 20,
    powerStoredEnergy: 0,
    powerRequiredEnergy: 10,
    castleBuilt: false,
    castleHp: 70,
    maxCastleHp: 70,
    shieldBuilt: false,
    shieldHp: 0,
    maxShieldHp: 100,
    powerBuilt: false,
    energyPerTick: 2,
    energyLevel: 0,
    reserveLevel: 0,
    minionDamage: 5,
    damageLevel: 0,
    spawnLevel: 0,
    spawnTimer: 0,
    spawnInterval: 3,
  };
}

function buildOrbs() {
  const orbs = [];
  for (let i = 0; i < 54; i += 1) {
    const column = i % 9;
    const row = Math.floor(i / 9);
    orbs.push({
      x: ARENA.x - 6100 + column * 1450 + Math.random() * 420,
      y: ARENA.y - 4300 + row * 1700 + Math.random() * 420,
      radius: 26,
      energy: 1,
      kind: "energy",
    });
  }
  return orbs;
}

function buildCrystals() {
  return [
    { x: ARENA.x - 2800, y: ARENA.y - 2400, radius: 95, hp: 60, maxHp: 60, respawnTimer: 0, active: true, hitSoundTimer: 0 },
    { x: ARENA.x + 2800, y: ARENA.y + 2400, radius: 95, hp: 60, maxHp: 60, respawnTimer: 0, active: true, hitSoundTimer: 0 },
    { x: ARENA.x + 3100, y: ARENA.y - 2100, radius: 95, hp: 60, maxHp: 60, respawnTimer: 0, active: true, hitSoundTimer: 0 },
    { x: ARENA.x - 3100, y: ARENA.y + 2100, radius: 95, hp: 60, maxHp: 60, respawnTimer: 0, active: true, hitSoundTimer: 0 },
    { x: ARENA.x, y: ARENA.y - 3450, radius: 95, hp: 60, maxHp: 60, respawnTimer: 0, active: true, hitSoundTimer: 0 },
    { x: ARENA.x, y: ARENA.y + 3450, radius: 95, hp: 60, maxHp: 60, respawnTimer: 0, active: true, hitSoundTimer: 0 },
  ];
}

function startQuickFight() {
  if (!network.lobbyConnected || getLocalLobbySlot() == null) {
    network.lastStatus = "Wait for the shared lobby to assign you a slot.";
    updateTitleLobbyUi();
    playErrorSound();
    return;
  }
  if (network.matchActive) {
    network.lastStatus = "A shared match is already running.";
    updateTitleLobbyUi();
    playErrorSound();
    return;
  }
  sendSocket({ type: "lobby_start" });
}

function resetToTitle() {
  if (network.mode === "match-host" || network.mode === "match-client") {
    sendSocket({ type: "match_end" });
  }
  network.mode = "pve";
  network.roomId = "";
  network.peerConnected = false;
  network.lastStatus = "";
  network.remoteInputs = {};
  STATE.game = null;
  STATE.mode = "title";
  basslineStep = 0;
  nextBasslineTime = 0;
  titleScreen.classList.remove("hidden");
  hud.classList.add("hidden");
  connectSocket();
  renderLobbySlots();
  syncHandleInputFromLobby();
  updateTitleLobbyUi();
}

quickFightButton.addEventListener("click", startQuickFight);
resetFightButton.addEventListener("click", resetToTitle);
handleInput?.addEventListener("input", sendLobbyHandle);
spawnWarriorButton.addEventListener("click", spawnWarriorFromUi);
castleUpgradeButton.addEventListener("click", upgradeCastleDamageFromUi);
powerUpgradeButton.addEventListener("click", upgradePowerplantFromUi);
powerReserveButton.addEventListener("click", upgradeReserveFromUi);

window.addEventListener("keydown", (event) => {
  unlockAudio();
  STATE.keys.add(event.code);
  if (network.mode === "match-client") {
    sendSocket({ type: "input", input: collectNetworkInput() });
  }
  if (event.code === "Escape" && STATE.mode === "round") {
    resetToTitle();
  }
});

window.addEventListener("keyup", (event) => {
  STATE.keys.delete(event.code);
  if (network.mode === "match-client") {
    sendSocket({ type: "input", input: collectNetworkInput() });
  }
});

window.addEventListener("pointerdown", unlockAudio);

canvas.addEventListener("pointerdown", (event) => {
  if (event.pointerType !== "touch" || STATE.mode !== "round") {
    return;
  }
  STATE.touchMove = {
    active: true,
    pointerId: event.pointerId,
    originX: event.clientX,
    originY: event.clientY,
    currentX: event.clientX,
    currentY: event.clientY,
  };
});

window.addEventListener("pointermove", (event) => {
  const rect = canvas.getBoundingClientRect();
  const sx = (event.clientX - rect.left) * (canvas.width / rect.width);
  const sy = (event.clientY - rect.top) * (canvas.height / rect.height);
  STATE.mouseWorld = screenToWorld(sx, sy);
  if (STATE.touchMove.active && event.pointerId === STATE.touchMove.pointerId) {
    STATE.touchMove.currentX = event.clientX;
    STATE.touchMove.currentY = event.clientY;
    if (network.mode === "match-client") {
      sendSocket({ type: "input", input: collectNetworkInput() });
    }
  }
});

window.addEventListener("pointerup", (event) => {
  if (STATE.touchMove.active && event.pointerId === STATE.touchMove.pointerId) {
    STATE.touchMove.active = false;
    STATE.touchMove.pointerId = null;
    if (network.mode === "match-client") {
      sendSocket({ type: "input", input: collectNetworkInput() });
    }
  }
});

window.addEventListener("pointercancel", (event) => {
  if (STATE.touchMove.active && event.pointerId === STATE.touchMove.pointerId) {
    STATE.touchMove.active = false;
    STATE.touchMove.pointerId = null;
  }
});

canvas.addEventListener("click", (event) => {
  if (STATE.mode !== "round" || !STATE.game) {
    return;
  }
  const rect = canvas.getBoundingClientRect();
  const sx = (event.clientX - rect.left) * (canvas.width / rect.width);
  const sy = (event.clientY - rect.top) * (canvas.height / rect.height);
  selectTargetAtPoint(screenToWorld(sx, sy));
});

window.addEventListener("resize", resizeCanvas);

function resizeCanvas() {
  canvas.width = window.innerWidth * window.devicePixelRatio;
  canvas.height = window.innerHeight * window.devicePixelRatio;
  canvas.style.width = `${window.innerWidth}px`;
  canvas.style.height = `${window.innerHeight}px`;
  applyResponsiveButtonLabels();
}

function renderLobbySlots() {
  if (!lobbySlots) {
    return;
  }
  lobbySlots.innerHTML = "";
  const temporaryHost = isTemporaryLobbyHost();
  for (let i = 0; i < 8; i += 1) {
    const slotState = STATE.lobby[i] ?? createEmptyLobbyState()[i];
    const isLocalSlot = slotState.clientId && slotState.clientId === network.clientId;
    const row = document.createElement("div");
    row.className = "lobby-slot";

    const name = document.createElement("div");
    name.className = "lobby-slot-name";
    name.title = `Area ${i + 1}`;
    name.style.background = getColorById(slotState.colorId).value;
    row.appendChild(name);

    const colorSelect = document.createElement("select");
    colorSelect.className = "lobby-color-select";
    const usedColors = new Set(
      STATE.lobby
        .map((slot, slotIndex) => (slotIndex === i || slot.type === "empty" ? null : slot.colorId))
        .filter(Boolean),
    );
    for (const color of LOBBY_COLORS) {
      const option = document.createElement("option");
      option.value = color.id;
      option.textContent = color.label;
      option.disabled = usedColors.has(color.id);
      option.selected = slotState.colorId === color.id;
      colorSelect.appendChild(option);
    }
    colorSelect.disabled = !isLocalSlot;
    colorSelect.addEventListener("change", () => {
      sendLobbyColor(colorSelect.value);
    });
    row.appendChild(colorSelect);

    const controls = document.createElement("div");
    controls.className = "lobby-slot-controls";
    const status = document.createElement("div");
    status.className = "lobby-status";
    if (slotState.type === "empty") {
      status.classList.add("empty");
      status.textContent = "Empty";
    } else if (isLocalSlot) {
      status.classList.add("active");
      status.textContent = sanitizeHandle(slotState.handle) || "You";
    } else if (slotState.type === "npc") {
      status.classList.add("remote");
      status.textContent = sanitizeHandle(slotState.handle) || `NPC ${i + 1}`;
    } else {
      status.classList.add("remote");
      status.textContent = sanitizeHandle(slotState.handle) || `Player ${i + 1}`;
    }
    controls.appendChild(status);

    if (!slotState.clientId && temporaryHost) {
      const npcButton = document.createElement("button");
      npcButton.type = "button";
      npcButton.className = "lobby-slot-button";
      npcButton.textContent = slotState.type === "npc" ? "Open" : "NPC";
      npcButton.addEventListener("click", () => {
        sendLobbySlotType(i, slotState.type === "npc" ? "empty" : "npc");
      });
      controls.appendChild(npcButton);
    }

    row.appendChild(controls);
    lobbySlots.appendChild(row);
  }
}

function applyResponsiveButtonLabels() {
  const mobile = window.innerWidth <= 900;
  document.querySelectorAll(".button-label").forEach((node) => {
    node.textContent = mobile ? node.dataset.mobile || node.textContent : node.dataset.desktop || node.textContent;
  });
}

function getHumanPlayer() {
  if (!STATE.game) {
    return null;
  }
  const team = network.localTeam || 1;
  return STATE.game.players.find((player) => player.team === team && !player.dead) ?? null;
}

function screenToWorld(screenX, screenY) {
  const game = STATE.game;
  if (!game) {
    return { x: screenX, y: screenY };
  }
  const cam = game.camera;
  return {
    x: cam.x + (screenX - canvas.width / 2) / cam.zoom,
    y: cam.y + (screenY - canvas.height / 2) / cam.zoom,
  };
}

function worldToScreen(x, y) {
  const cam = STATE.game.camera;
  return {
    x: (x - cam.x) * cam.zoom + canvas.width / 2,
    y: (y - cam.y) * cam.zoom + canvas.height / 2,
  };
}

function update(dt) {
  if (STATE.mode !== "round" || !STATE.game) {
    return;
  }

  const game = STATE.game;

  if (network.mode === "match-client") {
    updateCamera(game, dt);
    updateHud(game);
    updateBaseControls(game);
    return;
  }

  game.roundTime += dt;
  game.tickTimer += dt;
  updateBassline();

  if (network.mode === "match-host") {
    for (const player of game.players) {
      if (player.team === network.localTeam || player.dead) {
        continue;
      }
      player.remoteInput = network.remoteInputs[player.team] ?? { left: false, right: false, up: false, down: false, dash: false, deposit: false };
    }
  }

  while (game.tickTimer >= 1) {
    game.tickTimer -= 1;
    applyTick(game);
  }

  for (const player of game.players) {
    updatePlayer(player, dt, game);
  }

  for (const pad of game.pads) {
    updatePad(pad, dt, game);
  }

  for (const minion of game.minions) {
    updateMinion(minion, dt, game);
  }
  updateMinionClashes(game);

  game.minions = game.minions.filter((minion) => !minion.dead);

  updateOrbs(game);
  updateCrystals(game, dt);
  updateFloatingText(game, dt);
  updateParticles(game, dt);
  updateCamera(game, dt);
  updateHud(game);
  updateBaseControls(game);
  if (network.mode === "match-host") {
    const now = performance.now();
    if (now - network.lastSnapshotSentAt > 80) {
      network.lastSnapshotSentAt = now;
      sendSocket({ type: "snapshot", state: serializeGameState(game) });
    }
  }
  checkRoundEnd(game);
}

function updatePlayer(player, dt, game) {
  if (player.dead) {
    return;
  }

  player.rotation += player.spinSpeed * dt;
  player.bodyHitCooldown = Math.max(0, player.bodyHitCooldown - dt);
  player.dashCooldown = Math.max(0, player.dashCooldown - dt);
  player.armFlashTimer = Math.max(0, player.armFlashTimer - dt);
  player.bodyFlashTimer = Math.max(0, player.bodyFlashTimer - dt);

  for (const [key, value] of player.armDamageCooldown.entries()) {
    const next = value - dt;
    if (next <= 0) {
      player.armDamageCooldown.delete(key);
    } else {
      player.armDamageCooldown.set(key, next);
    }
  }

  if (player.controlType === "local") {
    const move = getHumanInput(collectNetworkInput());
    const norm = normalize(move.x, move.y);
    player.vx = norm.x * player.moveSpeed;
    player.vy = norm.y * player.moveSpeed;

    if (STATE.keys.has("ShiftLeft") && player.dashCooldown <= 0 && player.energy >= 3) {
      player.energy -= 3;
      player.dashCooldown = 0.45;
      const dashDir = normalize(Math.cos(player.rotation), Math.sin(player.rotation));
      player.x += dashDir.x * 120;
      player.y += dashDir.y * 120;
    }

    if (STATE.keys.has("KeyE")) {
      depositEnergy(player, game);
    }
  } else if (player.controlType === "remote") {
    const move = getHumanInput(player.remoteInput);
    const norm = normalize(move.x, move.y);
    player.vx = norm.x * player.moveSpeed;
    player.vy = norm.y * player.moveSpeed;

    if (player.remoteInput.dash && player.dashCooldown <= 0 && player.energy >= 3) {
      player.energy -= 3;
      player.dashCooldown = 0.45;
      const dashDir = normalize(Math.cos(player.rotation), Math.sin(player.rotation));
      player.x += dashDir.x * 120;
      player.y += dashDir.y * 120;
    }

    if (player.remoteInput.deposit) {
      depositEnergy(player, game);
    }
  } else {
    updateAiPlayer(player, dt, game);
  }

  player.x += player.vx * dt;
  player.y += player.vy * dt;
  confineToArena(player, player.radius + 14);

  handlePlayerCombat(player, game);
}

function getHumanInput(inputState = collectNetworkInput()) {
  let x = 0;
  let y = 0;
  if (inputState.left) x -= 1;
  if (inputState.right) x += 1;
  if (inputState.up) y -= 1;
  if (inputState.down) y += 1;
  return { x, y };
}

function updateAiPlayer(player, dt, game) {
  player.vx = 0;
  player.vy = 0;
  return;

  const enemy = game.players.find((candidate) => candidate.team !== player.team && !candidate.dead);
  if (!enemy) {
    player.vx = 0;
    player.vy = 0;
    return;
  }

  const dx = enemy.x - player.x;
  const dy = enemy.y - player.y;
  const dir = normalize(dx, dy);
  player.rotation = Math.atan2(dir.y, dir.x);
  player.vx = dir.x * player.moveSpeed * 0.72;
  player.vy = dir.y * player.moveSpeed * 0.72;
}

function depositEnergy(player, game) {
  const pad = game.pads.find((candidate) => candidate.team === player.team);
  if (!pad || player.energy <= 0) {
    return;
  }
  const shieldBox = getShieldBuildBox(pad);
  const powerBox = getPowerBuildBox(pad);
  const nearCastleBox = Math.abs(player.x - pad.x) <= pad.size && Math.abs(player.y - pad.y) <= pad.size;
  const nearShieldBox = Math.abs(player.x - shieldBox.x) <= shieldBox.size && Math.abs(player.y - shieldBox.y) <= shieldBox.size;
  const nearPowerBox = Math.abs(player.x - powerBox.x) <= powerBox.size && Math.abs(player.y - powerBox.y) <= powerBox.size;
  if (!nearCastleBox && !nearShieldBox && !nearPowerBox) {
    return;
  }
  if (nearShieldBox && !pad.shieldBuilt) {
    pad.shieldStoredEnergy = clamp(pad.shieldStoredEnergy + player.energy, 0, pad.shieldRequiredEnergy);
    player.energy = 0;
    if (pad.shieldStoredEnergy >= pad.shieldRequiredEnergy) {
      pad.shieldBuilt = true;
      pad.shieldHp = pad.maxShieldHp;
      spawnFloatingText(game, shieldBox.x, shieldBox.y - 140, "shield up", COLORS.healing);
      playCastleBuildSound();
    }
    return;
  }

  if (nearPowerBox && !pad.powerBuilt) {
    pad.powerStoredEnergy = clamp(pad.powerStoredEnergy + player.energy, 0, pad.powerRequiredEnergy);
    player.energy = 0;
    if (pad.powerStoredEnergy >= pad.powerRequiredEnergy) {
      pad.powerBuilt = true;
      spawnFloatingText(game, powerBox.x, powerBox.y - 140, "power on", COLORS.healing);
      playCastleBuildSound();
    }
    return;
  }

  if (nearCastleBox && !pad.castleBuilt) {
    pad.storedEnergy = clamp(pad.storedEnergy + player.energy, 0, pad.requiredEnergy);
    player.energy = 0;
    if (pad.storedEnergy >= pad.requiredEnergy) {
      pad.castleBuilt = true;
      pad.castleHp = pad.maxCastleHp;
      pad.spawnTimer = pad.spawnInterval;
      playCastleBuildSound();
    }
  }
}

function getShieldBuildBox(pad) {
  return {
    x: pad.x + pad.inwardX * BASE_LAYOUT.shieldFromCastle,
    y: pad.y + pad.inwardY * BASE_LAYOUT.shieldFromCastle,
    size: 130,
  };
}

function getPowerBuildBox(pad) {
  return {
    x: pad.x - pad.inwardX * BASE_LAYOUT.powerFromCastle,
    y: pad.y - pad.inwardY * BASE_LAYOUT.powerFromCastle,
    size: 120,
  };
}

function flashUpgradeError(button) {
  if (!button) {
    return;
  }
  button.classList.remove("flash-error");
  void button.offsetWidth;
  button.classList.add("flash-error");
  window.setTimeout(() => {
    button.classList.remove("flash-error");
  }, 180);
  playErrorSound();
}

function getOwnPad(game) {
  const player = game ? getHumanPlayer() : null;
  if (!game || !player) {
    return null;
  }
  return game.pads.find((candidate) => candidate.team === player.team) ?? null;
}

function selectTargetAtPoint(point) {
  const player = getHumanPlayer();
  if (!STATE.game || !player) {
    return;
  }
  const target = STATE.game.players.find((candidate) => candidate.team !== player.team && !candidate.dead && distance(point, candidate) <= candidate.radius + 24);
  STATE.selectedTargetTeam = target?.team ?? null;
}

function issueAttackTarget(targetTeam) {
  STATE.selectedTargetTeam = targetTeam;
  if (STATE.game) {
    const localPlayer = getHumanPlayer();
    updateTargetList(STATE.game, localPlayer);
  }
  if (network.mode === "match-client") {
    sendSocket({ type: "action", action: { type: "attack_warriors", targetTeam } });
    return;
  }
  performWarriorAttackForTeam(network.localTeam, targetTeam);
}

function spawnWarriorFromUi() {
  if (network.mode === "match-client") {
    sendSocket({ type: "action", action: { type: "spawn_warrior" } });
    return;
  }
  performSpawnWarriorForTeam(network.localTeam);
}

function upgradeCastleDamageFromUi() {
  if (network.mode === "match-client") {
    sendSocket({ type: "action", action: { type: "castle_upgrade" } });
    return;
  }
  performCastleUpgradeForTeam(network.localTeam);
}

function upgradePowerplantFromUi() {
  if (network.mode === "match-client") {
    sendSocket({ type: "action", action: { type: "power_upgrade" } });
    return;
  }
  performPowerUpgradeForTeam(network.localTeam);
}

function upgradeReserveFromUi() {
  if (network.mode === "match-client") {
    sendSocket({ type: "action", action: { type: "power_reserve" } });
    return;
  }
  performReserveUpgradeForTeam(network.localTeam);
}

function handleRemoteAction(action) {
  if (!STATE.game) {
    return;
  }
  const team = action.team;
  if (team == null) {
    return;
  }
  if (action.type === "spawn_warrior") {
    performSpawnWarriorForTeam(team);
  } else if (action.type === "castle_upgrade") {
    performCastleUpgradeForTeam(team);
  } else if (action.type === "power_upgrade") {
    performPowerUpgradeForTeam(team);
  } else if (action.type === "power_reserve") {
    performReserveUpgradeForTeam(team);
  } else if (action.type === "attack_warriors") {
    performWarriorAttackForTeam(team, action.targetTeam);
  }
}

function getTeamMinionCount(game, team) {
  return game.minions.filter((minion) => minion.team === team && !minion.dead).length;
}

function performSpawnWarriorForTeam(team) {
  const game = STATE.game;
  const pad = game?.pads.find((candidate) => candidate.team === team);
  const player = game?.players.find((candidate) => candidate.team === team && !candidate.dead);
  if (!game || !pad || !player || !pad.castleBuilt || player.energy < 4 || getTeamMinionCount(game, team) >= 20) {
    if (team === network.localTeam) {
      flashUpgradeError(spawnWarriorButton);
    }
    return;
  }
  player.energy -= 4;
  spawnWarrior(pad, game);
}

function performWarriorAttackForTeam(team, targetTeam) {
  const game = STATE.game;
  const attacker = game?.players.find((candidate) => candidate.team === team && !candidate.dead);
  const target = game?.players.find((candidate) => candidate.team === targetTeam && !candidate.dead);
  if (!game || !attacker || !target || attacker.team === target.team) {
    if (team === network.localTeam) {
      playErrorSound();
    }
    return;
  }
  let issued = 0;
  for (const minion of game.minions) {
    if (minion.team !== team || minion.dead) {
      continue;
    }
    minion.targetTeam = targetTeam;
    minion.dormant = false;
    issued += 1;
  }
  if (!issued && team === network.localTeam) {
    playErrorSound();
    return;
  }
  if (team === network.localTeam) {
    STATE.selectedTargetTeam = targetTeam;
  }
}

function performCastleUpgradeForTeam(team) {
  const game = STATE.game;
  const pad = game?.pads.find((candidate) => candidate.team === team);
  const player = game?.players.find((candidate) => candidate.team === team && !candidate.dead);
  if (!game || !pad || !player || !pad.castleBuilt || player.energy < 4) {
    if (team === network.localTeam) {
      flashUpgradeError(castleUpgradeButton);
    }
    return;
  }
  player.energy -= 4;
  pad.minionDamage += 1;
  pad.damageLevel += 1;
  spawnFloatingText(game, pad.x, pad.y - 220, `damage ${pad.minionDamage}`, COLORS.healing);
  playArmPickupSound();
}

function performPowerUpgradeForTeam(team) {
  const game = STATE.game;
  const pad = game?.pads.find((candidate) => candidate.team === team);
  const player = game?.players.find((candidate) => candidate.team === team && !candidate.dead);
  if (!game || !pad || !player || !pad.powerBuilt || player.energy < 20) {
    if (team === network.localTeam) {
      flashUpgradeError(powerUpgradeButton);
    }
    return;
  }
  player.energy -= 20;
  pad.energyPerTick += 1;
  pad.energyLevel += 1;
  const powerBox = getPowerBuildBox(pad);
  spawnFloatingText(game, powerBox.x, powerBox.y - 170, `energy ${pad.energyPerTick}`, COLORS.healing);
  playArmPickupSound();
}

function performReserveUpgradeForTeam(team) {
  const game = STATE.game;
  const pad = game?.pads.find((candidate) => candidate.team === team);
  const player = game?.players.find((candidate) => candidate.team === team && !candidate.dead);
  if (!game || !pad || !player || !pad.powerBuilt || player.energy < 20) {
    if (team === network.localTeam) {
      flashUpgradeError(powerReserveButton);
    }
    return;
  }
  player.energy -= 20;
  player.maxEnergy += 20;
  pad.reserveLevel += 1;
  const powerBox = getPowerBuildBox(pad);
  spawnFloatingText(game, powerBox.x, powerBox.y - 210, `reserve ${player.maxEnergy}`, COLORS.healing);
  playArmPickupSound();
}

function applyTick(game) {
  for (const pad of game.pads) {
    if (!pad.powerBuilt) {
      continue;
    }
    const owner = game.players.find((player) => player.team === pad.team && !player.dead);
    if (!owner) {
      continue;
    }
    owner.energy = clamp(owner.energy + pad.energyPerTick, 0, owner.maxEnergy);
    const powerBox = getPowerBuildBox(pad);
    spawnFloatingText(game, powerBox.x, powerBox.y - 170, `+${pad.energyPerTick}`, COLORS.healing);
  }
}

function getShieldData(pad) {
  const shieldBox = getShieldBuildBox(pad);
  const centerX = shieldBox.x + pad.inwardX * 260;
  const centerY = shieldBox.y + pad.inwardY * 260;
  const radius = BASE_LAYOUT.shieldArcRadius;
  const thickness = BASE_LAYOUT.shieldArcThickness;
  const arcHalfSpan = 1.22;
  const facingAngle = pad.facingAngle;
  return {
    centerX,
    centerY,
    radius,
    thickness,
    startAngle: facingAngle - arcHalfSpan,
    endAngle: facingAngle + arcHalfSpan,
    facingAngle,
    arcHalfSpan,
  };
}

function normalizeAngle(angle) {
  let value = angle;
  while (value > Math.PI) value -= Math.PI * 2;
  while (value < -Math.PI) value += Math.PI * 2;
  return value;
}

function hitsShield(minion, pad) {
  if (!pad.shieldBuilt || minion.team === pad.team) {
    return false;
  }
  const shield = getShieldData(pad);
  const dx = minion.x - shield.centerX;
  const dy = minion.y - shield.centerY;
  const dist = Math.hypot(dx, dy);
  const angle = Math.atan2(dy, dx);
  const arcDelta = Math.abs(normalizeAngle(angle - shield.facingAngle));
  return arcDelta <= shield.arcHalfSpan && Math.abs(dist - shield.radius) <= shield.thickness + minion.radius;
}

function getArmSegments(player) {
  const count = player.arms.length;
  const segments = [];
  for (let i = 0; i < count; i += 1) {
    const angleStep = (Math.PI * 2) / Math.max(count, 1);
    const angle = player.rotation + angleStep * i;
    const fromX = player.x + Math.cos(angle) * player.radius;
    const fromY = player.y + Math.sin(angle) * player.radius;
    const toX = player.x + Math.cos(angle) * (player.radius + player.armLength);
    const toY = player.y + Math.sin(angle) * (player.radius + player.armLength);
    segments.push({
      index: i,
      x1: fromX,
      y1: fromY,
      x2: toX,
      y2: toY,
      angle,
    });
  }
  return segments;
}

function handlePlayerCombat(player, game) {
  if (player.dead) {
    return;
  }
  const enemies = game.players.filter((candidate) => candidate.team !== player.team && !candidate.dead);
  const mySegments = getArmSegments(player);

  for (const enemy of enemies) {
    const enemySegments = getArmSegments(enemy);

    for (const mySeg of mySegments) {
      for (const enemySeg of enemySegments) {
        const clashKey = `${enemy.id}:${mySeg.index}:${enemySeg.index}`;
        if (player.armDamageCooldown.has(clashKey)) {
          continue;
        }
        if (segmentCollision(mySeg, player.armWidth, enemySeg, enemy.armWidth)) {
          player.armDamageCooldown.set(clashKey, 0.12);
          enemy.armDamageCooldown.set(`${player.id}:${enemySeg.index}:${mySeg.index}`, 0.12);
          playSwordClashSound();
          damageArm(player, mySeg.index, 20, game, player.x, player.y);
          damageArm(enemy, enemySeg.index, 20, game, enemy.x, enemy.y);
          nudge(player, enemy, 26);
        }
      }

      if (segmentPointDistance(mySeg.x1, mySeg.y1, mySeg.x2, mySeg.y2, enemy.x, enemy.y) <= player.armWidth + enemy.radius) {
        if (enemy.bodyHitCooldown <= 0) {
          enemy.bodyHitCooldown = 0.2;
          applyBodyHit(enemy, 30, game, player.x, player.y);
          nudge(player, enemy, 42);
        }
      }
    }
  }
}

function damageArm(player, armIndex, amount, game, sourceX, sourceY) {
  const arm = player.arms[armIndex];
  if (!arm) {
    return;
  }
  arm.hp -= amount;
  if (arm.hp <= 20 && !arm.crack) {
    arm.crack = true;
  }
  player.armFlashTimer = 0.08;
  if (arm.hp <= 0) {
    spawnFloatingText(game, sourceX, sourceY - 24, "-arm");
    player.arms.splice(armIndex, 1);
    if (player.arms.length <= 0) {
      player.dead = true;
    }
  }
}

function applyBodyHit(player, amount, game, sourceX, sourceY) {
  player.bodyHp -= amount;
  player.bodyFlashTimer = 0.1;
  if (player.arms.length > 1) {
    const nearestIndex = nearestArmIndex(player, sourceX, sourceY);
    damageArm(player, nearestIndex, 999, game, player.x, player.y);
  }
  if (player.bodyHp <= 0) {
    player.dead = true;
  }
}

function nearestArmIndex(player, sourceX, sourceY) {
  const segments = getArmSegments(player);
  let best = 0;
  let bestDist = Infinity;
  for (const seg of segments) {
    const d = Math.hypot(seg.x2 - sourceX, seg.y2 - sourceY);
    if (d < bestDist) {
      bestDist = d;
      best = seg.index;
    }
  }
  return best;
}

function nudge(a, b, amount) {
  const dir = normalize(b.x - a.x, b.y - a.y);
  a.x -= dir.x * amount;
  a.y -= dir.y * amount;
  b.x += dir.x * amount;
  b.y += dir.y * amount;
  confineToArena(a, a.radius + 14);
  confineToArena(b, b.radius + 14);
}

function confineToArena(entity, padding = 0) {
  const dx = entity.x - ARENA.x;
  const dy = entity.y - ARENA.y;
  const dist = Math.hypot(dx, dy) || 1;
  const limit = ARENA.radius - padding;
  if (dist <= limit) {
    return;
  }
  const scale = limit / dist;
  entity.x = ARENA.x + dx * scale;
  entity.y = ARENA.y + dy * scale;
}

function updatePad(pad, dt, game) {
  void dt;
  void game;
}

function spawnWarrior(pad, game) {
  game.minions.push({
    type: "minion",
    team: pad.team,
    x: pad.x + pad.inwardX * BASE_LAYOUT.dormantMinionOffset + pad.tangentX * ((Math.random() - 0.5) * 180),
    y: pad.y + pad.inwardY * BASE_LAYOUT.dormantMinionOffset + pad.tangentY * ((Math.random() - 0.5) * 180),
    radius: 30,
    speed: 1320,
    dead: false,
    damage: pad.minionDamage,
    spinAngle: Math.random() * Math.PI * 2,
    spinSpeed: 9,
    dormant: true,
    targetTeam: null,
  });
  playMinionSpawnSound();
}

function updateMinion(minion, dt, game) {
  if (minion.dead) {
    return;
  }
  minion.spinAngle += minion.spinSpeed * dt;
  if (minion.dormant || !minion.targetTeam) {
    confineToArena(minion, minion.radius + 8);
    return;
  }
  const enemy = game.players.find((player) => player.team === minion.targetTeam && !player.dead);
  if (!enemy) {
    minion.dormant = true;
    minion.targetTeam = null;
    return;
  }
  const enemyPad = game.pads.find((pad) => pad.team === minion.targetTeam);
  if (enemyPad && hitsShield(minion, enemyPad)) {
    enemyPad.shieldHp = Math.max(0, enemyPad.shieldHp - 5);
    spawnFloatingText(game, minion.x, minion.y - 55, "-5 shield");
    minion.dead = true;
    if (enemyPad.shieldHp <= 0) {
      enemyPad.shieldBuilt = false;
      spawnFloatingText(game, enemyPad.x, enemyPad.y - 240, "shield down");
    }
    return;
  }
  const dir = normalize(enemy.x - minion.x, enemy.y - minion.y);
  minion.x += dir.x * minion.speed * dt;
  minion.y += dir.y * minion.speed * dt;
  confineToArena(minion, minion.radius + 8);
  if (circleCollision(minion, minion.radius, enemy, enemy.radius)) {
    enemy.bodyFlashTimer = 0.1;
    enemy.bodyHp -= minion.damage;
    if (enemy.bodyHp <= 0) {
      enemy.dead = true;
    }
    if (enemy.arms.length > 0) {
      const nearestIndex = nearestArmIndex(enemy, minion.x, minion.y);
      damageArm(enemy, nearestIndex, minion.damage, game, enemy.x, enemy.y);
    }
    const push = normalize(enemy.x - minion.x, enemy.y - minion.y);
    enemy.x += push.x * 16;
    enemy.y += push.y * 16;
    confineToArena(enemy, enemy.radius + 14);
    spawnFloatingText(game, minion.x, minion.y - 70, `-${minion.damage} hp`);
    minion.dead = true;
  }
}

function updateMinionClashes(game) {
  for (let i = 0; i < game.minions.length; i += 1) {
    const a = game.minions[i];
    if (a.dead) {
      continue;
    }
    for (let j = i + 1; j < game.minions.length; j += 1) {
      const b = game.minions[j];
      if (b.dead || a.team === b.team) {
        continue;
      }
      if (circleCollision(a, a.radius, b, b.radius)) {
        a.dead = true;
        b.dead = true;
        spawnFloatingText(game, (a.x + b.x) * 0.5, (a.y + b.y) * 0.5 - 24, "clash");
        break;
      }
    }
  }
}

function updateOrbs(game) {
  for (const player of game.players) {
    if (player.dead) {
      continue;
    }
    for (let i = game.orbs.length - 1; i >= 0; i -= 1) {
      const orb = game.orbs[i];
      if (circleCollision(player, player.radius, orb, orb.radius)) {
        if (orb.kind === "arm") {
          if (player.arms.length < MAX_ARMS) {
            player.arms.push({ hp: 40, maxHp: 40, crack: false });
            spawnFloatingText(game, player.x, player.y - 90, "+arm", COLORS.healing);
            playArmPickupSound();
          } else {
            spawnFloatingText(game, player.x, player.y - 90, "max arms", COLORS.healing);
          }
        } else {
          player.energy = clamp(player.energy + orb.energy, 0, player.maxEnergy);
          spawnFloatingText(game, player.x, player.y - 90, "+1 en", COLORS.healing);
        }
        game.orbs.splice(i, 1);
      }
    }
  }
}

function updateCrystals(game, dt) {
  for (const crystal of game.crystals) {
    crystal.hitSoundTimer = Math.max(0, (crystal.hitSoundTimer ?? 0) - dt);
    if (!crystal.active) {
      crystal.respawnTimer -= dt;
      if (crystal.respawnTimer <= 0) {
        crystal.active = true;
        crystal.hp = crystal.maxHp;
        crystal.hitSoundTimer = 0;
      }
      continue;
    }
    for (const player of game.players) {
      if (player.dead) {
        continue;
      }
      const segments = getArmSegments(player);
      for (const segment of segments) {
        if (segmentPointDistance(segment.x1, segment.y1, segment.x2, segment.y2, crystal.x, crystal.y) <= player.armWidth + crystal.radius) {
          crystal.hp -= 1.25;
          if (crystal.hitSoundTimer <= 0) {
            playCrystalHitSound();
            crystal.hitSoundTimer = 0.06;
          }
          const push = normalize(player.x - crystal.x, player.y - crystal.y);
          player.x += push.x * 3;
          player.y += push.y * 3;
          confineToArena(player, player.radius + 14);
          if (crystal.hp <= 0) {
            crystal.active = false;
            crystal.respawnTimer = 5;
            spawnFloatingText(game, crystal.x, crystal.y - 110, "shatter", COLORS.healing);
            game.orbs.push({
              x: crystal.x + (Math.random() - 0.5) * 80,
              y: crystal.y + (Math.random() - 0.5) * 80,
              radius: 28,
              energy: 0,
              kind: "arm",
            });
          }
          break;
        }
      }
    }
  }
}

function updateFloatingText(game, dt) {
  for (const item of game.floatingText) {
    item.life -= dt;
    item.y -= 30 * dt;
  }
  game.floatingText = game.floatingText.filter((item) => item.life > 0);
}

function updateParticles(game, dt) {
  for (const particle of game.particles) {
    particle.life -= dt;
    particle.x += particle.vx * dt;
    particle.y += particle.vy * dt;
  }
  game.particles = game.particles.filter((particle) => particle.life > 0);
}

function spawnFloatingText(game, x, y, text, color = COLORS.damage) {
  game.floatingText.push({ x, y, text, color, life: 0.6 });
}

function updateCamera(game, dt) {
  const player = getHumanPlayer() ?? game.players[0];
  if (!player) {
    return;
  }
  game.camera.x = lerp(game.camera.x, player.x, Math.min(1, dt * 6));
  game.camera.y = lerp(game.camera.y, player.y, Math.min(1, dt * 6));
  game.camera.zoom = canvas.width < 1100 ? 0.34 * window.devicePixelRatio : 0.48 * window.devicePixelRatio;
  const halfWidth = canvas.width / (2 * game.camera.zoom);
  const halfHeight = canvas.height / (2 * game.camera.zoom);
  game.camera.x = clamp(game.camera.x, halfWidth, WORLD.width - halfWidth);
  game.camera.y = clamp(game.camera.y, halfHeight, WORLD.height - halfHeight);
}

function updateHud(game) {
  const player = getHumanPlayer();
  if (!player) {
    playerStats.textContent = "Defeated";
    return;
  }
  const pad = game.pads.find((candidate) => candidate.team === player.team);
  const shieldText = pad?.shieldBuilt ? ` | Shield ${Math.max(0, Math.ceil(pad.shieldHp))}` : "";
  const powerText = pad?.powerBuilt ? ` | Plant +${pad.energyPerTick}` : "";
  playerStats.textContent = `HP ${Math.max(0, Math.ceil(player.bodyHp))} | EN ${player.energy}/${player.maxEnergy} | Arms ${player.arms.length}${shieldText}${powerText}`;
  if (game.winner) {
    statusText.textContent = `${game.winner} wins`;
    return;
  }
  if (network.mode === "match-host") {
    statusText.textContent = network.lastStatus || `Hosting shared match | Players ${game.players.filter((player) => !player.dead).length}`;
    return;
  }
  if (network.mode === "match-client") {
    statusText.textContent = network.lastStatus || `Shared match | Slot ${network.localTeam}`;
    return;
  }
  statusText.textContent = `Minions ${game.minions.length} | E deposit at castle, shield, or powerplant`;
}

function updateBaseControls(game) {
  const player = getHumanPlayer();
  const pad = player ? game.pads.find((candidate) => candidate.team === player.team) : null;
  if (!player || !pad) {
    castleState.textContent = "Unavailable";
    powerplantState.textContent = "Unavailable";
    spawnWarriorButton.classList.add("is-unaffordable");
    castleUpgradeButton.classList.add("is-unaffordable");
    powerUpgradeButton.classList.add("is-unaffordable");
    powerReserveButton.classList.add("is-unaffordable");
    updateTargetList(game, null);
    return;
  }

  const target = game.players.find((candidate) => candidate.team === STATE.selectedTargetTeam && !candidate.dead);
  const teamMinions = getTeamMinionCount(game, player.team);
  castleState.textContent = pad.castleBuilt
    ? `Built | Dmg ${pad.minionDamage} | Triangles ${teamMinions}/20${target ? ` | Target ${target.nickname}` : ""}`
    : `Not built | ${pad.storedEnergy}/${pad.requiredEnergy}`;
  powerplantState.textContent = pad.powerBuilt
    ? `Built | Energy +${pad.energyPerTick} | Reserve ${player.maxEnergy}`
    : `Not built | ${pad.powerStoredEnergy}/${pad.powerRequiredEnergy}`;

  spawnWarriorButton.classList.toggle("is-unaffordable", !pad.castleBuilt || player.energy < 4 || teamMinions >= 20);
  castleUpgradeButton.classList.toggle("is-unaffordable", !pad.castleBuilt || player.energy < 4);
  powerUpgradeButton.classList.toggle("is-unaffordable", !pad.powerBuilt || player.energy < 20);
  powerReserveButton.classList.toggle("is-unaffordable", !pad.powerBuilt || player.energy < 20);
  updateTargetList(game, player);
}

function updateTargetList(game, localPlayer) {
  if (!targetList) {
    return;
  }
  targetList.innerHTML = "";
  if (!game || !localPlayer) {
    const empty = document.createElement("div");
    empty.className = "target-empty";
    empty.textContent = "No targets";
    targetList.appendChild(empty);
    return;
  }

  const localPad = game.pads.find((candidate) => candidate.team === localPlayer.team);
  const teamMinions = getTeamMinionCount(game, localPlayer.team);
  const enemies = game.players.filter((candidate) => candidate.team !== localPlayer.team && !candidate.dead);
  if (!enemies.length) {
    const empty = document.createElement("div");
    empty.className = "target-empty";
    empty.textContent = "No enemy players";
    targetList.appendChild(empty);
    return;
  }

  for (const enemy of enemies) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "target-entry";
    if (STATE.selectedTargetTeam === enemy.team) {
      button.classList.add("active");
    }
    button.disabled = !localPad?.castleBuilt || teamMinions <= 0;
    button.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      event.stopPropagation();
      issueAttackTarget(enemy.team);
    });

    const swatch = document.createElement("span");
    swatch.className = "target-swatch";
    swatch.style.background = enemy.color;
    button.appendChild(swatch);

    const label = document.createElement("span");
    label.textContent = enemy.nickname;
    button.appendChild(label);

    targetList.appendChild(button);
  }
}

function checkRoundEnd(game) {
  const alive = game.players.filter((player) => !player.dead);
  if (alive.length <= 1 && !game.winner) {
    game.winner = alive[0]?.nickname ?? "Nobody";
  }
}

function draw() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  drawBackground();
  if (STATE.mode !== "round" || !STATE.game) {
    return;
  }
  drawArena(STATE.game);
  drawMinimap(STATE.game);
}

function drawBackground() {
  const gradient = ctx.createLinearGradient(0, 0, 0, canvas.height);
  gradient.addColorStop(0, "#04070d");
  gradient.addColorStop(1, "#010203");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  ctx.fillStyle = "rgba(255,255,255,0.5)";
  for (let i = 0; i < 80; i += 1) {
    const x = (i * 137) % canvas.width;
    const y = (i * 271) % canvas.height;
    ctx.fillRect(x, y, 2, 2);
  }
}

function drawArena(game) {
  ctx.save();
  ctx.translate(canvas.width / 2, canvas.height / 2);
  ctx.scale(game.camera.zoom, game.camera.zoom);
  ctx.translate(-game.camera.x, -game.camera.y);

  const arenaGradient = ctx.createRadialGradient(
    ARENA.x,
    ARENA.y,
    ARENA.radius * 0.12,
    ARENA.x,
    ARENA.y,
    ARENA.radius,
  );
  arenaGradient.addColorStop(0, "rgba(34, 68, 118, 0.28)");
  arenaGradient.addColorStop(0.7, "rgba(24, 48, 92, 0.18)");
  arenaGradient.addColorStop(1, "rgba(5, 10, 18, 0.02)");
  ctx.fillStyle = arenaGradient;
  ctx.beginPath();
  ctx.arc(ARENA.x, ARENA.y, ARENA.radius, 0, Math.PI * 2);
  ctx.fill();

  ctx.strokeStyle = "rgba(154, 214, 255, 0.22)";
  ctx.lineWidth = 28;
  ctx.beginPath();
  ctx.arc(ARENA.x, ARENA.y, ARENA.radius, 0, Math.PI * 2);
  ctx.stroke();

  drawPads(game);
  drawCrystals(game);
  drawOrbs(game);
  drawPlayers(game);
  drawMinions(game);
  drawFloatingText(game);

  ctx.restore();
}

function drawMinimap(game) {
  const mobile = window.innerWidth <= 900;
  const size = mobile ? 132 * window.devicePixelRatio : 176 * window.devicePixelRatio;
  const margin = mobile ? 10 * window.devicePixelRatio : 14 * window.devicePixelRatio;
  const x = canvas.width - size - margin;
  const y = margin;
  const centerX = x + size / 2;
  const centerY = y + size / 2;
  const radius = size * 0.42;

  ctx.save();

  ctx.fillStyle = "rgba(8, 12, 18, 0.82)";
  ctx.strokeStyle = "rgba(141, 225, 255, 0.24)";
  ctx.lineWidth = 2 * window.devicePixelRatio;
  roundRectPath(x, y, size, size, 18 * window.devicePixelRatio);
  ctx.fill();
  ctx.stroke();

  const radarGradient = ctx.createRadialGradient(centerX, centerY, radius * 0.16, centerX, centerY, radius);
  radarGradient.addColorStop(0, "rgba(38, 90, 168, 0.24)");
  radarGradient.addColorStop(1, "rgba(4, 10, 20, 0.02)");
  ctx.fillStyle = radarGradient;
  ctx.beginPath();
  ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
  ctx.fill();

  ctx.strokeStyle = "rgba(154, 214, 255, 0.3)";
  ctx.lineWidth = 1.5 * window.devicePixelRatio;
  ctx.beginPath();
  ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
  ctx.stroke();

  ctx.beginPath();
  ctx.arc(centerX, centerY, radius * 0.66, 0, Math.PI * 2);
  ctx.stroke();

  ctx.beginPath();
  ctx.moveTo(centerX - radius, centerY);
  ctx.lineTo(centerX + radius, centerY);
  ctx.moveTo(centerX, centerY - radius);
  ctx.lineTo(centerX, centerY + radius);
  ctx.stroke();

  const localPlayer = getHumanPlayer();
  for (const player of game.players) {
    if (player.dead) {
      continue;
    }
    const dx = (player.x - ARENA.x) / ARENA.radius;
    const dy = (player.y - ARENA.y) / ARENA.radius;
    const px = centerX + dx * radius;
    const py = centerY + dy * radius;
    const dotRadius = (player === localPlayer ? 5.5 : 4) * window.devicePixelRatio;

    ctx.fillStyle = player.bodyFlashTimer > 0 ? COLORS.uiDanger : player.color;
    ctx.beginPath();
    ctx.arc(px, py, dotRadius, 0, Math.PI * 2);
    ctx.fill();

    if (player === localPlayer) {
      ctx.strokeStyle = "rgba(255,255,255,0.95)";
      ctx.lineWidth = 1.5 * window.devicePixelRatio;
      ctx.beginPath();
      ctx.arc(px, py, dotRadius + 3 * window.devicePixelRatio, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  ctx.fillStyle = "rgba(244, 246, 251, 0.88)";
  ctx.font = `${11 * window.devicePixelRatio}px Segoe UI`;
  ctx.textAlign = "left";
  ctx.fillText("MINIMAP", x + 10 * window.devicePixelRatio, y + 16 * window.devicePixelRatio);

  ctx.restore();
}

function roundRectPath(x, y, width, height, radius) {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + width - radius, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
  ctx.lineTo(x + width, y + height - radius);
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  ctx.lineTo(x + radius, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
  ctx.lineTo(x, y + radius);
  ctx.quadraticCurveTo(x, y, x + radius, y);
  ctx.closePath();
}

function drawPads(game) {
  for (const pad of game.pads) {
    const shield = getShieldData(pad);
    const shieldBox = getShieldBuildBox(pad);
    const powerBox = getPowerBuildBox(pad);
    ctx.save();
    ctx.translate(pad.x, pad.y);
    ctx.fillStyle = "rgba(255,255,255,0.08)";
    ctx.strokeStyle = pad.team === 1 ? "#90e7ff" : "#ffc68d";
    ctx.lineWidth = 12;
    ctx.fillRect(-pad.size, -pad.size, pad.size * 2, pad.size * 2);
    ctx.strokeRect(-pad.size, -pad.size, pad.size * 2, pad.size * 2);

    if (pad.castleBuilt) {
      ctx.save();
      ctx.rotate(pad.facingAngle + Math.PI / 2);
      ctx.fillStyle = pad.team === 1 ? COLORS.castle : COLORS.castleEnemy;
      ctx.fillRect(
        -CASTLE_DRAW.bodyWidth / 2,
        CASTLE_DRAW.bodyTop,
        CASTLE_DRAW.bodyWidth,
        CASTLE_DRAW.bodyHeight,
      );
      ctx.fillRect(
        -CASTLE_DRAW.sideTowerOffsetX - CASTLE_DRAW.towerWidth / 2,
        CASTLE_DRAW.sideTowerTop,
        CASTLE_DRAW.towerWidth,
        CASTLE_DRAW.towerHeight,
      );
      ctx.fillRect(
        -CASTLE_DRAW.centerTowerWidth / 2,
        CASTLE_DRAW.centerTowerTop,
        CASTLE_DRAW.centerTowerWidth,
        CASTLE_DRAW.centerTowerHeight,
      );
      ctx.fillRect(
        CASTLE_DRAW.sideTowerOffsetX - CASTLE_DRAW.towerWidth / 2,
        CASTLE_DRAW.sideTowerTop,
        CASTLE_DRAW.towerWidth,
        CASTLE_DRAW.towerHeight,
      );
      ctx.restore();
    }

    ctx.fillStyle = "#f6f7fb";
    ctx.font = "42px Segoe UI";
    ctx.textAlign = "center";
    ctx.fillText(`${pad.storedEnergy}/${pad.requiredEnergy}`, 0, -pad.size - 26);
    ctx.restore();

    ctx.save();
    ctx.translate(shieldBox.x, shieldBox.y);
    ctx.fillStyle = "rgba(255,255,255,0.05)";
    ctx.strokeStyle = pad.team === 1 ? "#7ed9ff" : "#ffd09d";
    ctx.lineWidth = 10;
    ctx.fillRect(-shieldBox.size, -shieldBox.size, shieldBox.size * 2, shieldBox.size * 2);
    ctx.strokeRect(-shieldBox.size, -shieldBox.size, shieldBox.size * 2, shieldBox.size * 2);
    ctx.fillStyle = "#eefaff";
    ctx.font = "34px Segoe UI";
    ctx.textAlign = "center";
    ctx.fillText(`${pad.shieldStoredEnergy}/${pad.shieldRequiredEnergy}`, 0, -shieldBox.size - 20);
    ctx.font = "28px Segoe UI";
    ctx.fillText("Shield", 0, shieldBox.size + 42);
    ctx.restore();

    ctx.save();
    ctx.translate(powerBox.x, powerBox.y);
    ctx.fillStyle = "rgba(180, 255, 186, 0.05)";
    ctx.strokeStyle = "#91ef9c";
    ctx.lineWidth = 10;
    ctx.fillRect(-powerBox.size, -powerBox.size, powerBox.size * 2, powerBox.size * 2);
    ctx.strokeRect(-powerBox.size, -powerBox.size, powerBox.size * 2, powerBox.size * 2);
    ctx.fillStyle = "#ecffef";
    ctx.font = "34px Segoe UI";
    ctx.textAlign = "center";
    ctx.fillText(`${pad.powerStoredEnergy}/${pad.powerRequiredEnergy}`, 0, -powerBox.size - 20);
    ctx.font = "26px Segoe UI";
    ctx.fillText("Powerplant", 0, powerBox.size + 40);
    if (pad.powerBuilt) {
      ctx.fillStyle = "#a3ffc8";
      ctx.fillText(`+${pad.energyPerTick}`, 0, powerBox.size + 74);
    }
    ctx.restore();

    if (pad.shieldBuilt) {
      ctx.save();
      ctx.strokeStyle = pad.team === 1 ? "rgba(130, 224, 255, 0.82)" : "rgba(255, 205, 138, 0.82)";
      ctx.lineWidth = shield.thickness * 2;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(shield.centerX, shield.centerY, shield.radius, shield.startAngle, shield.endAngle);
      ctx.stroke();

      ctx.strokeStyle = "rgba(255,255,255,0.28)";
      ctx.lineWidth = 8;
      ctx.beginPath();
      ctx.arc(shield.centerX, shield.centerY, shield.radius, shield.startAngle, shield.endAngle);
      ctx.stroke();

      ctx.fillStyle = "#eafcff";
      ctx.font = "30px Segoe UI";
      ctx.textAlign = "center";
      ctx.fillText(`Shield ${Math.max(0, Math.ceil(pad.shieldHp))}`, pad.x, pad.y + pad.size + 54);
      ctx.restore();
    }
  }
}

function drawOrbs(game) {
  for (const orb of game.orbs) {
    ctx.fillStyle = orb.kind === "arm" ? "#8fd6ff" : COLORS.orb;
    ctx.beginPath();
    ctx.arc(orb.x, orb.y, orb.radius, 0, Math.PI * 2);
    ctx.fill();
    if (orb.kind === "arm") {
      ctx.strokeStyle = "#ecfbff";
      ctx.lineWidth = 5;
      ctx.beginPath();
      ctx.moveTo(orb.x - 10, orb.y + 10);
      ctx.lineTo(orb.x, orb.y - 12);
      ctx.lineTo(orb.x + 10, orb.y + 10);
      ctx.stroke();
    }
  }
}

function drawCrystals(game) {
  for (const crystal of game.crystals) {
    if (!crystal.active) {
      continue;
    }
    ctx.save();
    ctx.translate(crystal.x, crystal.y);
    ctx.fillStyle = COLORS.crystal;
    ctx.beginPath();
    ctx.moveTo(0, -110);
    ctx.lineTo(80, -10);
    ctx.lineTo(52, 102);
    ctx.lineTo(-52, 102);
    ctx.lineTo(-80, -10);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = COLORS.crystalCore;
    ctx.beginPath();
    ctx.moveTo(0, -90);
    ctx.lineTo(55, -10);
    ctx.lineTo(34, 78);
    ctx.lineTo(-34, 78);
    ctx.lineTo(-55, -10);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
}

function drawPlayers(game) {
  for (const player of game.players) {
    if (player.dead) {
      continue;
    }
    const color = player.bodyFlashTimer > 0 ? COLORS.uiDanger : player.color;
    const armColor = player.armFlashTimer > 0 ? COLORS.uiDanger : color;
    const segments = getArmSegments(player);

    for (let i = 0; i < segments.length; i += 1) {
      const seg = segments[i];
      const arm = player.arms[i];
      ctx.strokeStyle = armColor;
      ctx.lineWidth = player.armWidth * 2;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(seg.x1, seg.y1);
      ctx.lineTo(seg.x2, seg.y2);
      ctx.stroke();

      if (arm?.crack) {
        ctx.strokeStyle = COLORS.crack;
        ctx.lineWidth = 6;
        ctx.beginPath();
        ctx.moveTo(lerp(seg.x1, seg.x2, 0.12), lerp(seg.y1, seg.y2, 0.12));
        ctx.lineTo(lerp(seg.x1, seg.x2, 0.42), lerp(seg.y1, seg.y2, 0.42) + 12);
        ctx.lineTo(lerp(seg.x1, seg.x2, 0.68), lerp(seg.y1, seg.y2, 0.68) - 10);
        ctx.lineTo(lerp(seg.x1, seg.x2, 0.92), lerp(seg.y1, seg.y2, 0.92));
        ctx.stroke();
      }
    }

    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(player.x, player.y, player.radius, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#101318";
    ctx.font = "34px Segoe UI";
    ctx.textAlign = "center";
    ctx.fillText(player.nickname, player.x, player.y - player.radius - 30);
  }
}

function drawMinions(game) {
  for (const minion of game.minions) {
    ctx.save();
    ctx.translate(minion.x, minion.y);
    ctx.rotate(minion.spinAngle);
    ctx.fillStyle = "rgba(255,255,255,0.08)";
    ctx.beginPath();
    ctx.arc(0, 0, minion.radius + 12, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = minion.team === 1 ? COLORS.minion : COLORS.minionEnemy;
    ctx.beginPath();
    ctx.moveTo(0, -minion.radius - 8);
    ctx.lineTo(minion.radius + 10, minion.radius);
    ctx.lineTo(-minion.radius - 10, minion.radius);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = "#fffaf2";
    ctx.beginPath();
    ctx.moveTo(0, -minion.radius * 0.6);
    ctx.lineTo(minion.radius * 0.45, minion.radius * 0.35);
    ctx.lineTo(-minion.radius * 0.45, minion.radius * 0.35);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
}

function drawFloatingText(game) {
  for (const item of game.floatingText) {
    ctx.save();
    ctx.globalAlpha = clamp(item.life / 0.6, 0, 1);
    ctx.fillStyle = item.color;
    ctx.font = "32px Segoe UI";
    ctx.textAlign = "center";
    ctx.fillText(item.text, item.x, item.y);
    ctx.restore();
  }
}

let previous = performance.now();
function frame(now) {
  const dt = Math.min((now - previous) / 1000, 0.033);
  previous = now;
  update(dt);
  draw();
  requestAnimationFrame(frame);
}

resizeCanvas();
renderLobbySlots();
applyResponsiveButtonLabels();
syncHandleInputFromLobby();
updateTitleLobbyUi();
connectSocket();
requestAnimationFrame(frame);
