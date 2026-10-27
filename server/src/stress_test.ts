/**
 * Stress test for Chain Revival multiplayer server.
 *
 * Usage:
 *   1. Start the server:  cd server && npm run dev
 *   2. In another terminal: npx tsx server/src/stress_test.ts
 *
 * Options (env vars):
 *   SERVER_URL   default ws://127.0.0.1:3000
 *   TIERS        comma-separated client counts, default "2,10,20,50"
 *   DURATION_SEC per-tier duration, default 30
 */

import WebSocket from "ws";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const SERVER_URL = process.env.SERVER_URL ?? "ws://127.0.0.1:3000";
const TIERS = (process.env.TIERS ?? "2,10,20,50").split(",").map(Number);
const DURATION_SEC = Number(process.env.DURATION_SEC ?? "30");
const COMMAND_INTERVAL_MS = 200; // each client sends a command every 200ms

const MATCH_ID = "local-mp-1";
const MAP_WIDTH = 30;
const MAP_HEIGHT = 30;

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

interface TierMetrics {
  tier: number;
  connectTimeMs: number[];
  pingLatencyMs: number[];
  messagesSent: number;
  messagesReceived: number;
  errors: number;
  disconnects: number;
  serverMemoryStart: NodeJS.MemoryUsage | null;
  serverMemoryEnd: NodeJS.MemoryUsage | null;
}

function emptyMetrics(tier: number): TierMetrics {
  return {
    tier,
    connectTimeMs: [],
    pingLatencyMs: [],
    messagesSent: 0,
    messagesReceived: 0,
    errors: 0,
    disconnects: 0,
    serverMemoryStart: null,
    serverMemoryEnd: null,
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function randomCell(): { x: number; y: number } {
  return {
    x: Math.floor(Math.random() * MAP_WIDTH),
    y: Math.floor(Math.random() * MAP_HEIGHT),
  };
}

let requestSeq = 0;
function nextRequestId(): string {
  return `stress-${++requestSeq}`;
}

function randomSide(): "USA" | "GERMANY" {
  return Math.random() < 0.5 ? "USA" : "GERMANY";
}

/** Build a random command that the server can parse. */
function randomCommand(teamId: number): object {
  const roll = Math.random();
  const soldierId = Math.floor(Math.random() * 4) + 1;

  if (roll < 0.35) {
    // move_command
    return {
      type: "move_command",
      matchId: MATCH_ID,
      requestId: nextRequestId(),
      teamId,
      soldierId,
      targetCell: randomCell(),
      scope: 0,
      movementMode: Math.random() < 0.7 ? 0 : 1, // run or walk
    };
  } else if (roll < 0.55) {
    // face_command
    return {
      type: "face_command",
      matchId: MATCH_ID,
      requestId: nextRequestId(),
      teamId,
      soldierId,
      targetCell: randomCell(),
      scope: 0,
      aimWorld: null,
    };
  } else if (roll < 0.70) {
    // position_command (up/down)
    return {
      type: "position_command",
      matchId: MATCH_ID,
      requestId: nextRequestId(),
      teamId,
      soldierId,
      positionState: Math.random() < 0.5 ? 0 : 1,
    };
  } else if (roll < 0.82) {
    // fire_control_command (hold / at will)
    return {
      type: "fire_control_command",
      matchId: MATCH_ID,
      requestId: nextRequestId(),
      teamId,
      soldierId,
      fireControlState: Math.random() < 0.5 ? 0 : 1,
    };
  } else if (roll < 0.92) {
    // fire_at_command
    const enemyTeam = teamId === 1 ? 2 : 1;
    return {
      type: "fire_at_command",
      matchId: MATCH_ID,
      requestId: nextRequestId(),
      teamId,
      soldierId,
      targetTeamId: enemyTeam,
      targetSoldierId: Math.floor(Math.random() * 4) + 1,
      scope: 0,
      targetCell: randomCell(),
      aimWorld: null,
    };
  } else {
    // grenade_command
    return {
      type: "grenade_command",
      matchId: MATCH_ID,
      requestId: nextRequestId(),
      teamId,
      soldierId,
      targetCell: randomCell(),
    };
  }
}

// ---------------------------------------------------------------------------
// Simulated client
// ---------------------------------------------------------------------------

interface StressClient {
  ws: WebSocket;
  teamId: number;
  interval: NodeJS.Timeout | null;
  sentCount: number;
  recvCount: number;
  errors: number;
  disconnected: boolean;
  connectTimeMs: number;
  pingLatencies: number[];
}

function connectClient(url: string, metrics: TierMetrics): Promise<StressClient> {
  return new Promise((resolve, reject) => {
    const startMs = performance.now();
    const ws = new WebSocket(url);
    const client: StressClient = {
      ws,
      teamId: 0,
      interval: null,
      sentCount: 0,
      recvCount: 0,
      errors: 0,
      disconnected: false,
      connectTimeMs: 0,
      pingLatencies: [],
    };

    const timeout = setTimeout(() => {
      ws.close();
      reject(new Error("Connection timeout after 10s"));
    }, 10_000);

    ws.on("open", () => {
      clearTimeout(timeout);
      client.connectTimeMs = performance.now() - startMs;
      // Send hello
      ws.send(JSON.stringify({ type: "hello", clientName: "StressBot" }));
      client.sentCount++;
    });

    let sideAttempts = 0;

    ws.on("message", (data) => {
      client.recvCount++;
      try {
        const msg = JSON.parse(data.toString());
        if (msg.type === "welcome") {
          // Request a side
          const side = randomSide();
          ws.send(JSON.stringify({ type: "request_side", side }));
          client.sentCount++;
        } else if (msg.type === "side_assigned") {
          client.teamId = msg.teamId;
          resolve(client);
        } else if (msg.type === "side_denied") {
          sideAttempts++;
          if (sideAttempts < 2) {
            // Try the other side
            const otherSide = sideAttempts === 1 ? "GERMANY" : "USA";
            ws.send(JSON.stringify({ type: "request_side", side: otherSide }));
            client.sentCount++;
          } else {
            // Both sides taken; resolve as observer (teamId stays 0, will just send pings)
            client.teamId = Math.random() < 0.5 ? 1 : 2; // fake team for commands
            resolve(client);
          }
        } else if (msg.type === "pong") {
          const sent = msg.echoTimestamp as number;
          if (typeof sent === "number") {
            client.pingLatencies.push(Date.now() - sent);
          }
        }
      } catch {
        client.errors++;
      }
    });

    ws.on("error", () => {
      client.errors++;
      metrics.errors++;
    });

    ws.on("close", () => {
      client.disconnected = true;
      if (client.interval) clearInterval(client.interval);
    });
  });
}

function startCommandLoop(client: StressClient): void {
  client.interval = setInterval(() => {
    if (client.ws.readyState !== WebSocket.OPEN || client.teamId === 0) return;

    // Send a game command
    const cmd = randomCommand(client.teamId);
    client.ws.send(JSON.stringify(cmd));
    client.sentCount++;

    // Periodic ping for latency measurement
    if (Math.random() < 0.1) {
      const ping = { type: "ping", echoTimestamp: Date.now() };
      client.ws.send(JSON.stringify(ping));
      client.sentCount++;
    }
  }, COMMAND_INTERVAL_MS);
}

function stopClient(client: StressClient): void {
  if (client.interval) {
    clearInterval(client.interval);
    client.interval = null;
  }
  if (client.ws.readyState === WebSocket.OPEN) {
    client.ws.close();
  }
}

// ---------------------------------------------------------------------------
// Tier runner
// ---------------------------------------------------------------------------

async function runTier(tierSize: number): Promise<TierMetrics> {
  const metrics = emptyMetrics(tierSize);

  console.log(`\n${"=".repeat(60)}`);
  console.log(`  TIER: ${tierSize} clients   Duration: ${DURATION_SEC}s`);
  console.log(`${"=".repeat(60)}`);

  // Connect all clients
  const clients: StressClient[] = [];
  const connectStart = performance.now();

  console.log(`  Connecting ${tierSize} clients...`);
  const connectPromises: Promise<StressClient>[] = [];
  for (let i = 0; i < tierSize; i++) {
    connectPromises.push(
      connectClient(SERVER_URL, metrics).catch((err) => {
        metrics.errors++;
        console.log(`  Client ${i} failed to connect: ${(err as Error).message}`);
        return null as unknown as StressClient;
      })
    );
    // Stagger connections slightly to avoid thundering herd
    await new Promise((r) => setTimeout(r, 50));
  }

  const results = await Promise.all(connectPromises);
  for (const c of results) {
    if (c && !c.disconnected) {
      clients.push(c);
      metrics.connectTimeMs.push(c.connectTimeMs);
    }
  }

  const connectElapsed = performance.now() - connectStart;
  console.log(
    `  ${clients.length}/${tierSize} connected in ${connectElapsed.toFixed(0)}ms`
  );

  if (clients.length === 0) {
    console.log("  No clients connected. Skipping tier.");
    return metrics;
  }

  // Start command loops
  for (const c of clients) {
    startCommandLoop(c);
  }

  // Let it run
  console.log(`  Running for ${DURATION_SEC}s...`);
  const samplesInterval = setInterval(() => {
    const alive = clients.filter((c) => !c.disconnected).length;
    const totalSent = clients.reduce((s, c) => s + c.sentCount, 0);
    const totalRecv = clients.reduce((s, c) => s + c.recvCount, 0);
    process.stdout.write(
      `\r  [${new Date().toLocaleTimeString()}] alive=${alive} sent=${totalSent} recv=${totalRecv}   `
    );
  }, 2000);

  await new Promise((r) => setTimeout(r, DURATION_SEC * 1000));
  clearInterval(samplesInterval);
  console.log();

  // Collect metrics
  for (const c of clients) {
    metrics.messagesSent += c.sentCount;
    metrics.messagesReceived += c.recvCount;
    metrics.errors += c.errors;
    if (c.disconnected) metrics.disconnects++;
    metrics.pingLatencyMs.push(...c.pingLatencies);
  }

  // Cleanup
  for (const c of clients) {
    stopClient(c);
  }

  // Small delay for graceful disconnect
  await new Promise((r) => setTimeout(r, 500));

  return metrics;
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

function percentile(arr: number[], p: number): number {
  if (arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const idx = Math.floor((p / 100) * (sorted.length - 1));
  return sorted[idx];
}

function avg(arr: number[]): number {
  if (arr.length === 0) return 0;
  return arr.reduce((s, v) => s + v, 0) / arr.length;
}

function printReport(allMetrics: TierMetrics[]): void {
  console.log(`\n${"=".repeat(70)}`);
  console.log("  STRESS TEST REPORT");
  console.log(`${"=".repeat(70)}`);
  console.log(`  Server: ${SERVER_URL}`);
  console.log(`  Duration per tier: ${DURATION_SEC}s`);
  console.log(`  Command interval: ${COMMAND_INTERVAL_MS}ms per client`);
  console.log();

  const header = [
    "Clients",
    "Connected",
    "Disconn",
    "Errors",
    "Sent",
    "Recv",
    "ConnAvg(ms)",
    "PingAvg(ms)",
    "PingP95(ms)",
    "Throughput(msg/s)",
  ];
  console.log(
    `  ${header.map((h) => h.padStart(12)).join("")}`
  );
  console.log(`  ${"-".repeat(12 * header.length)}`);

  for (const m of allMetrics) {
    const connected = m.connectTimeMs.length;
    const connAvg = avg(m.connectTimeMs);
    const pingAvg = avg(m.pingLatencyMs);
    const pingP95 = percentile(m.pingLatencyMs, 95);
    const throughput = (m.messagesReceived / DURATION_SEC).toFixed(1);

    const row = [
      m.tier.toString(),
      connected.toString(),
      m.disconnects.toString(),
      m.errors.toString(),
      m.messagesSent.toString(),
      m.messagesReceived.toString(),
      connAvg.toFixed(1),
      pingAvg.toFixed(1),
      pingP95.toFixed(1),
      throughput,
    ];
    console.log(`  ${row.map((v) => v.padStart(12)).join("")}`);
  }

  console.log();

  // Highlight issues
  let issues = 0;
  for (const m of allMetrics) {
    if (m.disconnects > 0) {
      console.log(
        `  ⚠  Tier ${m.tier}: ${m.disconnects} unexpected disconnects`
      );
      issues++;
    }
    if (m.errors > 0) {
      console.log(`  ⚠  Tier ${m.tier}: ${m.errors} errors`);
      issues++;
    }
    const pingP95 = percentile(m.pingLatencyMs, 95);
    if (pingP95 > 100) {
      console.log(
        `  ⚠  Tier ${m.tier}: P95 ping latency ${pingP95.toFixed(0)}ms (>100ms)`
      );
      issues++;
    }
  }

  if (issues === 0) {
    console.log("  ✓  No issues detected across all tiers.");
  }

  console.log(`\n${"=".repeat(70)}\n`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  console.log("Chain Revival Multiplayer Server Stress Test");
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Tiers: ${TIERS.join(", ")} clients`);
  console.log(`Duration per tier: ${DURATION_SEC}s`);
  console.log();

  // Quick connectivity check
  try {
    const ws = new WebSocket(SERVER_URL);
    await new Promise<void>((resolve, reject) => {
      ws.on("open", () => {
        ws.close();
        resolve();
      });
      ws.on("error", reject);
      setTimeout(() => reject(new Error("timeout")), 5000);
    });
  } catch {
    console.error(
      `ERROR: Cannot connect to ${SERVER_URL}. Is the server running?`
    );
    process.exit(1);
  }
  console.log("Server is reachable. Starting stress test...\n");

  const allMetrics: TierMetrics[] = [];

  for (const tier of TIERS) {
    const metrics = await runTier(tier);
    allMetrics.push(metrics);

    // Pause between tiers for server to stabilize
    if (tier !== TIERS[TIERS.length - 1]) {
      console.log("  Pausing 3s between tiers...");
      await new Promise((r) => setTimeout(r, 3000));
    }
  }

  printReport(allMetrics);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
