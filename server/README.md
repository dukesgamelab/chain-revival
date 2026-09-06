# Chain Revival — Local Multiplayer Server

Authoritative Node.js + TypeScript WebSocket server for LOCAL_MULTIPLAYER.

The server owns the match `GameState` and resolves `MoveCommand` through a
ported ActionResolver movement slice. Godot clients present results only.

## Requirements

- Node.js 18+

## Run locally

```bash
cd server
npm install
npm run dev
```

The server listens on `ws://localhost:3000` and creates one match (`local-mp-1`)
on Farm Fight (`ff_farm`).

## Two-window test

1. Start the server (`cd server && npm run dev`).
2. Launch two Godot editor instances of this project (or two exported builds).
3. In each window: **Multiplayer** → connect → pick **USA** or **GERMANY**.
4. Each side can only be taken once. Both windows receive the same snapshot.
5. USA issues Run To; both windows animate that soldier. Same for Germany.
6. USA cannot move German soldiers (server rejects). Vice versa.

## Scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Run with `tsx` (development) |
| `npm run build` | Compile TypeScript to `dist/` |
| `npm start` | Run compiled output (`node dist/index.js`) |

## Messages

| Direction | `type` | Role |
|-----------|--------|------|
| C→S | `hello` | Handshake; server replies `welcome` + `clientId` + `matchId` |
| C→S | `request_side` | `USA` / `GERMANY`; exclusive ownership |
| S→C | `side_assigned` / `side_denied` | Server-owned side |
| S→C | `match_snapshot` | Initial authoritative state (map id + soldiers) |
| C→S | `move_command` | Intent only (`requestId`, soldier, destination, mode, scope) |
| S→C | `move_result` | Broadcast ActionResult paths |
| S→C | `movement_tick` | Authoritative tile steps / completions |

Single-player / Offline Quick Start never talks to this server.
