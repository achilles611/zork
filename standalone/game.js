const canvas = document.getElementById("game");
const ctx = canvas.getContext("2d");

const titleScreen = document.getElementById("titleScreen");
const hud = document.getElementById("hud");
const quickFightButton = document.getElementById("quickFightButton");
const hostPvpButton = document.getElementById("hostPvpButton");
const joinPvpButton = document.getElementById("joinPvpButton");
const roomCodeInput = document.getElementById("roomCodeInput");
const resetFightButton = document.getElementById("resetFightButton");
const playerStats = document.getElementById("playerStats");
const statusText = document.getElementById("statusText");
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
  width: 19200,
  height: 13800,
};

const ARENA = {
  x: WORLD.width / 2,
  y: WORLD.height / 2,
  radius: 6150,
};

const MAX_ARMS = 8;

const STATE = {
  mode: "title",
  keys: new Set(),
  game: null,
  mouseWorld: { x: WORLD.width / 2, y: WORLD.height / 2 },
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
  roomId: "",
  localTeam: 1,
  remoteInput: { left: false, right: false, up: false, down: false, dash: false, deposit: false },
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

  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.type === "room_created") {
      network.mode = "pvp-host";
      network.localTeam = 1;
      network.roomId = message.roomId;
      startNetworkRound("host");
      statusText.textContent = `Hosting PvP room ${message.roomId}`;
    } else if (message.type === "room_joined") {
      network.mode = "pvp-guest";
      network.localTeam = 2;
      network.roomId = message.roomId;
      startNetworkRound("guest");
      statusText.textContent = `Joined PvP room ${message.roomId}`;
    } else if (message.type === "guest_joined") {
      statusText.textContent = `Guest joined room ${message.roomId}`;
    } else if (message.type === "input" && network.mode === "pvp-host") {
      network.remoteInput = message.input;
    } else if (message.type === "snapshot" && network.mode === "pvp-guest") {
      STATE.game = message.state;
    } else if (message.type === "action" && network.mode === "pvp-host") {
      handleRemoteAction(message.action);
    } else if (message.type === "peer_left") {
      statusText.textContent = "Peer disconnected";
      network.remoteInput = { left: false, right: false, up: false, down: false, dash: false, deposit: false };
    } else if (message.type === "error") {
      statusText.textContent = message.message;
      playErrorSound();
    }
  });

  socket.addEventListener("close", () => {
    if (network.socket === socket) {
      network.socket = null;
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
  return {
    left: STATE.keys.has("KeyA"),
    right: STATE.keys.has("KeyD"),
    up: STATE.keys.has("KeyW"),
    down: STATE.keys.has("KeyS"),
    dash: STATE.keys.has("ShiftLeft"),
    deposit: STATE.keys.has("KeyE"),
  };
}

function startNetworkRound(role) {
  STATE.game = spawnGame(role === "host" ? "pvp-host" : "pvp-guest");
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

function spawnGame(mode = "pve") {
  const playerStart = { x: ARENA.x - 2580, y: ARENA.y };
  const enemyStart = { x: ARENA.x + 2580, y: ARENA.y };
  const player = createPlayer({
    id: "player-1",
    team: 1,
    x: playerStart.x,
    y: playerStart.y,
    isHuman: true,
    controlType: "local",
    nickname: "Player 1",
  });
  const enemy = createPlayer({
    id: "player-2",
    team: 2,
    x: enemyStart.x,
    y: enemyStart.y,
    isHuman: mode === "pve" ? false : true,
    controlType: mode === "pve" ? "ai" : "remote",
    nickname: mode === "pve" ? "AI 2" : "Player 2",
  });

  return {
    camera: { x: player.x, y: player.y, zoom: 1 },
    players: [player, enemy],
    orbs: buildOrbs(),
    crystals: buildCrystals(),
    pads: [
      createCastlePad(1, playerStart.x - 750, playerStart.y),
      createCastlePad(2, enemyStart.x + 750, enemyStart.y),
    ],
    minions: [],
    particles: [],
    floatingText: [],
    roundTime: 0,
    tickTimer: 0,
    winner: null,
    npcSpawnCooldown: 0,
  };
}

function createPlayer({ id, team, x, y, isHuman, nickname, controlType = isHuman ? "local" : "ai" }) {
  return {
    type: "player",
    id,
    team,
    nickname,
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

function createCastlePad(team, x, y) {
  return {
    type: "pad",
    team,
    x,
    y,
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
    energyPerTick: 1,
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
  for (let i = 0; i < 28; i += 1) {
    const column = i % 7;
    const row = Math.floor(i / 7);
    orbs.push({
      x: ARENA.x - 3780 + column * 1260 + Math.random() * 360,
      y: ARENA.y - 2580 + row * 1560 + Math.random() * 360,
      radius: 26,
      energy: 1,
      kind: "energy",
    });
  }
  return orbs;
}

function buildCrystals() {
  return [
    { x: WORLD.width * 0.42, y: WORLD.height * 0.36, radius: 95, hp: 60, maxHp: 60, respawnTimer: 0, active: true, hitSoundTimer: 0 },
    { x: WORLD.width * 0.58, y: WORLD.height * 0.64, radius: 95, hp: 60, maxHp: 60, respawnTimer: 0, active: true, hitSoundTimer: 0 },
  ];
}

function startQuickFight() {
  network.mode = "pve";
  network.localTeam = 1;
  network.roomId = "";
  STATE.game = spawnGame();
  STATE.mode = "round";
  basslineStep = 0;
  const audio = getAudioContext();
  nextBasslineTime = audio ? audio.currentTime + 0.08 : 0;
  titleScreen.classList.add("hidden");
  hud.classList.remove("hidden");
}

function resetToTitle() {
  STATE.game = null;
  STATE.mode = "title";
  basslineStep = 0;
  nextBasslineTime = 0;
  titleScreen.classList.remove("hidden");
  hud.classList.add("hidden");
}

quickFightButton.addEventListener("click", startQuickFight);
hostPvpButton.addEventListener("click", () => {
  const socket = connectSocket();
  socket.addEventListener("open", function handleOpen() {
    socket.removeEventListener("open", handleOpen);
    sendSocket({ type: "host_room" });
  }, { once: true });
  if (socket.readyState === WebSocket.OPEN) {
    sendSocket({ type: "host_room" });
  }
});
joinPvpButton.addEventListener("click", () => {
  const roomId = roomCodeInput.value.trim();
  if (!roomId) {
    statusText.textContent = "Enter a room code";
    playErrorSound();
    return;
  }
  const socket = connectSocket();
  socket.addEventListener("open", function handleOpen() {
    socket.removeEventListener("open", handleOpen);
    sendSocket({ type: "join_room", roomId });
  }, { once: true });
  if (socket.readyState === WebSocket.OPEN) {
    sendSocket({ type: "join_room", roomId });
  }
});
resetFightButton.addEventListener("click", resetToTitle);
spawnWarriorButton.addEventListener("click", spawnWarriorFromUi);
castleUpgradeButton.addEventListener("click", upgradeCastleDamageFromUi);
powerUpgradeButton.addEventListener("click", upgradePowerplantFromUi);
powerReserveButton.addEventListener("click", upgradeReserveFromUi);

window.addEventListener("keydown", (event) => {
  unlockAudio();
  STATE.keys.add(event.code);
  if (network.mode === "pvp-guest") {
    sendSocket({ type: "input", input: collectNetworkInput() });
  }
  if (event.code === "Escape" && STATE.mode === "round") {
    resetToTitle();
  }
});

window.addEventListener("keyup", (event) => {
  STATE.keys.delete(event.code);
  if (network.mode === "pvp-guest") {
    sendSocket({ type: "input", input: collectNetworkInput() });
  }
});

window.addEventListener("pointerdown", unlockAudio);

window.addEventListener("pointermove", (event) => {
  const rect = canvas.getBoundingClientRect();
  const sx = (event.clientX - rect.left) * (canvas.width / rect.width);
  const sy = (event.clientY - rect.top) * (canvas.height / rect.height);
  STATE.mouseWorld = screenToWorld(sx, sy);
});

window.addEventListener("resize", resizeCanvas);

function resizeCanvas() {
  canvas.width = window.innerWidth * window.devicePixelRatio;
  canvas.height = window.innerHeight * window.devicePixelRatio;
  canvas.style.width = `${window.innerWidth}px`;
  canvas.style.height = `${window.innerHeight}px`;
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

  if (network.mode === "pvp-guest") {
    updateHud(game);
    updateBaseControls(game);
    return;
  }

  game.roundTime += dt;
  game.tickTimer += dt;
  updateBassline();

  if (network.mode === "pvp-host") {
    const remotePlayer = game.players.find((player) => player.team === 2);
    if (remotePlayer) {
      remotePlayer.remoteInput = network.remoteInput;
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

  game.minions = game.minions.filter((minion) => !minion.dead);

  updateOrbs(game);
  updateCrystals(game, dt);
  updateFloatingText(game, dt);
  updateParticles(game, dt);
  updateCamera(game, dt);
  updateHud(game);
  updateBaseControls(game);
  if (network.mode === "pvp-host") {
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
    x: pad.x + (pad.team === 1 ? 1040 : -1040),
    y: pad.y,
    size: 130,
  };
}

function getPowerBuildBox(pad) {
  return {
    x: pad.x + (pad.team === 1 ? -1040 : 1040),
    y: pad.y,
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

function spawnWarriorFromUi() {
  if (network.mode === "pvp-guest") {
    sendSocket({ type: "action", action: { type: "spawn_warrior" } });
    return;
  }
  performSpawnWarriorForTeam(network.localTeam);
}

function upgradeCastleDamageFromUi() {
  if (network.mode === "pvp-guest") {
    sendSocket({ type: "action", action: { type: "castle_upgrade" } });
    return;
  }
  performCastleUpgradeForTeam(network.localTeam);
}

function upgradePowerplantFromUi() {
  if (network.mode === "pvp-guest") {
    sendSocket({ type: "action", action: { type: "power_upgrade" } });
    return;
  }
  performPowerUpgradeForTeam(network.localTeam);
}

function upgradeReserveFromUi() {
  if (network.mode === "pvp-guest") {
    sendSocket({ type: "action", action: { type: "power_reserve" } });
    return;
  }
  performReserveUpgradeForTeam(network.localTeam);
}

function handleRemoteAction(action) {
  if (!STATE.game) {
    return;
  }
  if (action.type === "spawn_warrior") {
    performSpawnWarriorForTeam(2);
  } else if (action.type === "castle_upgrade") {
    performCastleUpgradeForTeam(2);
  } else if (action.type === "power_upgrade") {
    performPowerUpgradeForTeam(2);
  } else if (action.type === "power_reserve") {
    performReserveUpgradeForTeam(2);
  }
}

function performSpawnWarriorForTeam(team) {
  const game = STATE.game;
  const pad = game?.pads.find((candidate) => candidate.team === team);
  const player = game?.players.find((candidate) => candidate.team === team && !candidate.dead);
  if (!game || !pad || !player || !pad.castleBuilt || player.energy < 4) {
    if (team === network.localTeam) {
      flashUpgradeError(spawnWarriorButton);
    }
    return;
  }
  player.energy -= 4;
  spawnWarrior(pad, game);
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
  const centerX = shieldBox.x + (pad.team === 1 ? 240 : -240);
  const centerY = pad.y;
  const radius = 310;
  const thickness = 26;
  const arcHalfSpan = 1.22;
  const facingAngle = pad.team === 1 ? 0 : Math.PI;
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
  const spawnOffset = pad.team === 1 ? 180 : -180;
  game.minions.push({
    type: "minion",
    team: pad.team,
    x: pad.x + spawnOffset,
    y: pad.y - 40 + (Math.random() - 0.5) * 120,
    radius: 30,
    speed: 1320,
    dead: false,
    damage: pad.minionDamage,
    spinAngle: Math.random() * Math.PI * 2,
    spinSpeed: 9,
  });
  playMinionSpawnSound();
}

function updateMinion(minion, dt, game) {
  if (minion.dead) {
    return;
  }
  minion.spinAngle += minion.spinSpeed * dt;
  const enemy = game.players.find((player) => player.team !== minion.team && !player.dead);
  if (!enemy) {
    minion.dead = true;
    return;
  }

  const enemyPad = game.pads.find((pad) => pad.team !== minion.team);
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
  statusText.textContent = game.winner ? `${game.winner} wins` : `Minions ${game.minions.length} | E deposit at castle, shield, or powerplant`;
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
    return;
  }

  castleState.textContent = pad.castleBuilt
    ? `Built | Warrior damage ${pad.minionDamage}`
    : `Not built | ${pad.storedEnergy}/${pad.requiredEnergy}`;
  powerplantState.textContent = pad.powerBuilt
    ? `Built | Energy +${pad.energyPerTick} | Reserve ${player.maxEnergy}`
    : `Not built | ${pad.powerStoredEnergy}/${pad.powerRequiredEnergy}`;

  spawnWarriorButton.classList.toggle("is-unaffordable", !pad.castleBuilt || player.energy < 4);
  castleUpgradeButton.classList.toggle("is-unaffordable", !pad.castleBuilt || player.energy < 4);
  powerUpgradeButton.classList.toggle("is-unaffordable", !pad.powerBuilt || player.energy < 20);
  powerReserveButton.classList.toggle("is-unaffordable", !pad.powerBuilt || player.energy < 20);
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
    const color = player.bodyFlashTimer > 0 ? COLORS.uiDanger : (player.team === 1 ? COLORS.player : COLORS.enemy);
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
requestAnimationFrame(frame);
