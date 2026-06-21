# Chain Revival — Local Multiplayer Server

Node.js + TypeScript WebSocket server for local multiplayer. This is the foundation only: clients can connect and exchange a `ping` / `pong` handshake. Authoritative game logic will be added later.

## Requirements

- Node.js 18+

## Run locally

```bash
cd server
npm install
npm run dev
```

The server listens on `ws://localhost:3000` and logs:

```text
Chain Revival local multiplayer server running on ws://localhost:3000
```

## Scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Run with `tsx` (development) |
| `npm run build` | Compile TypeScript to `dist/` |
| `npm start` | Run compiled output (`node dist/index.js`) |

## Test message

Send from a WebSocket client:

```json
{ "type": "ping" }
```

Server responds:

```json
{ "type": "pong", "serverTime": 123456789 }
```

Hello handshake (used by Godot local multiplayer test):

```json
{ "type": "hello", "clientName": "Godot Client" }
```

Server responds:

```json
{ "type": "welcome", "message": "Hello Godot client", "clientId": "..." }
```

Side assignment:

```json
{ "type": "request_side", "side": "USA" }
```

Server responds with `{ "type": "side_assigned", "side": "USA" }` or `{ "type": "side_denied", "reason": "Side already taken" }`.

## Project layout

```text
src/
  index.ts           WebSocket server entry point
  game_state.ts      Placeholder (not ported from Godot)
  action_resolver.ts Placeholder (not ported from Godot)
  commands/index.ts  Placeholder command envelope types
```

The Godot client is unchanged and still runs offline gameplay as before.
