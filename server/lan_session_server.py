import asyncio
import json
import os
import ssl
import uuid
from pathlib import Path

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed


MAX_SLOTS = 8


class SessionServer:
    def __init__(self) -> None:
        self.clients: dict[str, dict] = {}
        self.phase = "lobby"
        self.host_client_id: str | None = None
        self.current_round_human_ids: set[str] = set()
        self.rematch_votes: set[str] = set()
        self.round_counter = 0
        self.slots = []
        self._reset_slots()

    def _reset_slots(self) -> None:
        self.slots = []
        for _ in range(MAX_SLOTS):
            self.slots.append({
                "nickname": "",
                "type": "open",
                "owner_id": None,
            })

    async def handler(self, websocket) -> None:
        client_id = uuid.uuid4().hex[:10]
        self.clients[client_id] = {
            "websocket": websocket,
            "nickname": f"Player {len(self.clients)}",
            "slot_index": None,
        }

        if self.host_client_id is None:
            self.host_client_id = client_id

        self._auto_assign_slot(client_id)
        await self._send(
            client_id,
            "welcome",
            {
                "client_id": client_id,
                "host_client_id": self.host_client_id,
            },
        )
        await self.broadcast_lobby_state()

        try:
            async for message in websocket:
                await self.handle_message(client_id, message)
        except ConnectionClosed:
            pass
        finally:
            await self.disconnect_client(client_id)

    async def handle_message(self, client_id: str, raw_message: str) -> None:
        try:
            parsed = json.loads(raw_message)
        except json.JSONDecodeError:
            return

        message_type = parsed.get("type", "")
        payload = parsed.get("payload", {}) or {}

        if message_type == "register":
            nickname = str(payload.get("nickname", "")).strip()
            if nickname:
                self.clients[client_id]["nickname"] = nickname
                slot_index = self.clients[client_id]["slot_index"]
                if slot_index is not None:
                    self.slots[slot_index]["nickname"] = nickname
            await self.broadcast_lobby_state()
        elif message_type == "claim_slot":
            await self.claim_slot(client_id, int(payload.get("slot_index", -1)))
        elif message_type == "set_nickname":
            nickname = str(payload.get("nickname", "")).strip()
            if nickname:
                self.clients[client_id]["nickname"] = nickname
                slot_index = self.clients[client_id]["slot_index"]
                if slot_index is not None:
                    self.slots[slot_index]["nickname"] = nickname
            await self.broadcast_lobby_state()
        elif message_type == "set_slot_type":
            if client_id == self.host_client_id:
                slot_index = int(payload.get("slot_index", -1))
                slot_type = str(payload.get("slot_type", "open"))
                await self.set_slot_type(slot_index, slot_type)
        elif message_type == "set_ai_nickname":
            if client_id == self.host_client_id:
                slot_index = int(payload.get("slot_index", -1))
                nickname = str(payload.get("nickname", "")).strip()
                if 0 <= slot_index < MAX_SLOTS and self.slots[slot_index]["type"] == "ai":
                    self.slots[slot_index]["nickname"] = nickname or f"AI {slot_index + 1}"
                    await self.broadcast_lobby_state()
        elif message_type == "start_match":
            if client_id == self.host_client_id:
                await self.start_match()
        elif message_type == "input_state":
            if self.host_client_id and client_id != self.host_client_id:
                await self._send(
                    self.host_client_id,
                    "remote_input",
                    {
                        "client_id": client_id,
                        "move": payload.get("move", [0.0, 0.0]),
                        "dash_pressed": bool(payload.get("dash_pressed", False)),
                    },
                )
        elif message_type == "round_snapshot":
            if client_id == self.host_client_id and self.phase in ("round", "round_end"):
                await self.broadcast("round_snapshot", payload, exclude={self.host_client_id})
        elif message_type == "end_round":
            if client_id == self.host_client_id:
                self.phase = "round_end"
                self.rematch_votes.clear()
                await self.broadcast("round_snapshot", payload, exclude={self.host_client_id})
                await self.broadcast_lobby_state()
        elif message_type == "run_again_vote":
            if client_id in self.current_round_human_ids:
                self.rematch_votes.add(client_id)
                if self.current_round_human_ids and self.current_round_human_ids.issubset(self.rematch_votes):
                    await self.start_match(reuse_existing=True)
                else:
                    await self.broadcast_lobby_state()
        elif message_type == "return_to_lobby":
            await self.return_to_lobby()
        elif message_type == "admin_set_energy":
            if self.phase not in ("round", "round_end"):
                return
            payload_to_host = {
                "client_id": client_id,
                "energy": int(payload.get("energy", 0)),
            }
            if self.host_client_id is not None and self.host_client_id != client_id:
                await self._send(self.host_client_id, "admin_set_energy", payload_to_host)

    async def disconnect_client(self, client_id: str) -> None:
        if client_id not in self.clients:
            return

        slot_index = self.clients[client_id]["slot_index"]
        if slot_index is not None:
            self.slots[slot_index] = {
                "nickname": "",
                "type": "open",
                "owner_id": None,
            }
        del self.clients[client_id]
        self.current_round_human_ids.discard(client_id)
        self.rematch_votes.discard(client_id)

        if client_id == self.host_client_id:
            self.host_client_id = next(iter(self.clients.keys()), None)
            if self.host_client_id is not None:
                self._ensure_host_slot()
            if self.phase in ("round", "round_end"):
                await self.return_to_lobby()
        await self.broadcast_lobby_state()

    def _auto_assign_slot(self, client_id: str) -> None:
        if client_id == self.host_client_id:
            self.slots[0] = {
                "nickname": self.clients[client_id]["nickname"],
                "type": "human",
                "owner_id": client_id,
            }
            self.clients[client_id]["slot_index"] = 0
            return

        for index in range(1, MAX_SLOTS):
            if self.slots[index]["type"] == "open" and self.slots[index]["owner_id"] is None:
                self.slots[index] = {
                    "nickname": self.clients[client_id]["nickname"],
                    "type": "human",
                    "owner_id": client_id,
                }
                self.clients[client_id]["slot_index"] = index
                return

    def _ensure_host_slot(self) -> None:
        if self.host_client_id is None:
            return
        host_nickname = self.clients[self.host_client_id]["nickname"]
        host_current_slot = self.clients[self.host_client_id]["slot_index"]
        if host_current_slot == 0:
            self.slots[0]["nickname"] = host_nickname
            self.slots[0]["type"] = "human"
            self.slots[0]["owner_id"] = self.host_client_id
            return

        if host_current_slot is not None:
            self.slots[host_current_slot] = {
                "nickname": "",
                "type": "open",
                "owner_id": None,
            }

        displaced_owner = self.slots[0]["owner_id"]
        self.slots[0] = {
            "nickname": host_nickname,
            "type": "human",
            "owner_id": self.host_client_id,
        }
        self.clients[self.host_client_id]["slot_index"] = 0

        if displaced_owner and displaced_owner in self.clients and displaced_owner != self.host_client_id:
            self.clients[displaced_owner]["slot_index"] = None
            self._auto_assign_slot(displaced_owner)

    async def claim_slot(self, client_id: str, slot_index: int) -> None:
        if slot_index < 0 or slot_index >= MAX_SLOTS:
            return
        if slot_index == 0 and client_id != self.host_client_id:
            return
        target_slot = self.slots[slot_index]
        if target_slot["owner_id"] not in (None, client_id):
            return
        if target_slot["type"] == "ai":
            return

        current_slot = self.clients[client_id]["slot_index"]
        if current_slot is not None and current_slot != 0:
            self.slots[current_slot] = {
                "nickname": "",
                "type": "open",
                "owner_id": None,
            }

        self.slots[slot_index] = {
            "nickname": self.clients[client_id]["nickname"],
            "type": "human",
            "owner_id": client_id,
        }
        self.clients[client_id]["slot_index"] = slot_index
        await self.broadcast_lobby_state()

    async def set_slot_type(self, slot_index: int, slot_type: str) -> None:
        if slot_index <= 0 or slot_index >= MAX_SLOTS:
            return
        if self.slots[slot_index]["owner_id"] is not None:
            return
        if slot_type not in ("open", "ai"):
            return
        if slot_type == "open":
            self.slots[slot_index] = {
                "nickname": "",
                "type": "open",
                "owner_id": None,
            }
        else:
            self.slots[slot_index] = {
                "nickname": f"AI {slot_index + 1}",
                "type": "ai",
                "owner_id": None,
            }
        await self.broadcast_lobby_state()

    async def start_match(self, reuse_existing: bool = False) -> None:
        participants = []
        human_ids = set()
        for index, slot in enumerate(self.slots):
            if slot["type"] == "open":
                continue
            participants.append({
                "slot_index": index,
                "nickname": slot["nickname"] or f"Player {index + 1}",
                "type": slot["type"],
                "owner_id": slot["owner_id"],
            })
            if slot["type"] == "human" and slot["owner_id"]:
                human_ids.add(slot["owner_id"])

        if len(participants) < 2:
            return

        self.phase = "round"
        self.current_round_human_ids = human_ids
        self.rematch_votes.clear()
        if not reuse_existing:
            self.round_counter += 1

        await self.broadcast(
            "match_started",
            {
                "phase": self.phase,
                "round_id": self.round_counter,
                "host_client_id": self.host_client_id,
                "participants": participants,
            },
        )
        await self.broadcast_lobby_state()

    async def return_to_lobby(self) -> None:
        self.phase = "lobby"
        self.current_round_human_ids.clear()
        self.rematch_votes.clear()
        await self.broadcast_lobby_state()

    async def broadcast_lobby_state(self) -> None:
        await self.broadcast(
            "lobby_state",
            {
                "phase": self.phase,
                "host_client_id": self.host_client_id,
                "slots": self.slots,
                "rematch_votes": list(self.rematch_votes),
            },
        )

    async def broadcast(self, message_type: str, payload: dict, exclude: set[str] | None = None) -> None:
        exclude = exclude or set()
        dead_clients = []
        for client_id, client in self.clients.items():
            if client_id in exclude:
                continue
            try:
                await client["websocket"].send(json.dumps({"type": message_type, "payload": payload}))
            except ConnectionClosed:
                dead_clients.append(client_id)
        for client_id in dead_clients:
            await self.disconnect_client(client_id)

    async def _send(self, client_id: str, message_type: str, payload: dict) -> None:
        client = self.clients.get(client_id)
        if client is None:
            return
        try:
            await client["websocket"].send(json.dumps({"type": message_type, "payload": payload}))
        except ConnectionClosed:
            await self.disconnect_client(client_id)


async def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    cert_path = project_root / "zork-local-https-cert.pem"
    key_path = project_root / "zork-local-https-key.pem"

    if not cert_path.exists() or not key_path.exists():
        raise SystemExit("PEM certificate files are missing. Run run_lan_session_server.ps1 once to prepare them.")

    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_context.load_cert_chain(certfile=os.fspath(cert_path), keyfile=os.fspath(key_path))

    server = SessionServer()
    async with serve(server.handler, "0.0.0.0", 8765, ssl=ssl_context, max_size=2**22):
        print("LAN session server listening on wss://0.0.0.0:8765")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
