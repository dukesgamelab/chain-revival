import assert from "node:assert/strict";
import { test } from "node:test";
import {
  clearDevLobbyState,
  clearDevRooms,
  hostDevRoom,
  isValidDevGuestId,
  joinDevRoom,
  leaveDevRoom,
  listDevOnline,
  listDevRooms,
  setDevPlayerConnected,
  setDevPlayerSide,
  touchDevPresence,
} from "../src/dev_lobby";

const HOST = "dev-guest-1111-aaaa1111";
const JOINER = "dev-guest-2222-bbbb2222";

function hostRoom(guestId = HOST, roomNumber = 1) {
  return hostDevRoom({
    devGuestId: guestId,
    displayName: "Guest 1111",
    roomNumber,
    matchName: "Guest 1111's Game",
    mapId: "ff_farm",
    teamSize: 1,
    matchLengthSec: 900,
    serverUrl: "ws://127.0.0.1:3000",
  });
}

test("dev guest ids are not account ids", () => {
  assert.equal(isValidDevGuestId(HOST), true);
  assert.equal(isValidDevGuestId("550e8400-e29b-41d4-a716-446655440000"), false);
  assert.equal(isValidDevGuestId(""), false);
  assert.equal(isValidDevGuestId("dev-guest-short"), false);
});

test("two guests can fill one development room", () => {
  clearDevRooms();
  const hosted = hostRoom();
  assert.equal(hosted.ok, true);
  if (!hosted.ok) return;
  assert.equal(hosted.room.status, "waiting");
  assert.equal(hosted.room.current_players, 1);
  assert.equal(hosted.room.server_url, "ws://127.0.0.1:3000");

  const joined = joinDevRoom(JOINER, "Guest 2222", 1);
  assert.equal(joined.ok, true);
  if (!joined.ok) return;
  assert.equal(joined.room.status, "in_progress");
  assert.equal(joined.room.current_players, 2);
  assert.equal(joined.room.host_id, HOST);
  assert.deepEqual(listDevRooms().map((room) => room.room_number), [1]);
});

test("a guest cannot host with a production server URL or a fake id", () => {
  clearDevRooms();
  const badId = hostDevRoom({
    devGuestId: "user-123",
    displayName: "Nope",
    roomNumber: 1,
    matchName: "Nope",
    mapId: "ff_farm",
    teamSize: 1,
    matchLengthSec: 900,
    serverUrl: "ws://127.0.0.1:3000",
  });
  assert.equal(badId.ok, false);

  const badUrl = hostDevRoom({
    devGuestId: HOST,
    displayName: "Guest",
    roomNumber: 1,
    matchName: "Guest",
    mapId: "ff_farm",
    teamSize: 1,
    matchLengthSec: 900,
    serverUrl: "https://chain-revival.example/lobby",
  });
  assert.equal(badUrl.ok, false);
  assert.equal(listDevRooms().length, 0);
});

test("the host leaving removes the room", () => {
  clearDevRooms();
  assert.equal(hostRoom().ok, true);
  assert.equal(leaveDevRoom(HOST).ok, true);
  assert.equal(listDevRooms().length, 0);
});

test("presence keeps one row per guest and drops stale sessions", () => {
  clearDevLobbyState();
  assert.equal(touchDevPresence(HOST, "Guest 1111", 1_000).ok, true);
  assert.equal(touchDevPresence(HOST, "Guest 1111", 1_500).ok, true);
  assert.equal(listDevOnline(1_500).length, 1);
  assert.equal(listDevOnline(1_500)[0]?.connected, true);

  const stale = listDevOnline(1_500 + 31_000);
  assert.equal(stale.length, 1);
  assert.equal(stale[0]?.connected, false);
  assert.equal(listDevOnline(1_500 + 91_000).length, 0);
});

test("room rosters show names and sides for every supported size", () => {
  clearDevLobbyState();
  const large = hostDevRoom({
    devGuestId: HOST,
    displayName: "Host",
    roomNumber: 3,
    matchName: "Large",
    mapId: "grand_battle",
    teamSize: 5,
    matchLengthSec: 900,
    serverUrl: "ws://127.0.0.1:3000",
  }, 5_000);
  assert.equal(large.ok, true);
  const medium = hostDevRoom({
    devGuestId: JOINER,
    displayName: "Joiner",
    roomNumber: 4,
    matchName: "Medium",
    mapId: "three_fields",
    teamSize: 3,
    matchLengthSec: 900,
    serverUrl: "ws://127.0.0.1:3000",
  }, 5_000);
  assert.equal(medium.ok, true);
  const unsupported = hostDevRoom({
    devGuestId: HOST,
    displayName: "Host",
    roomNumber: 5,
    matchName: "Nope",
    mapId: "ff_farm",
    teamSize: 4,
    matchLengthSec: 900,
    serverUrl: "ws://127.0.0.1:3000",
  });
  assert.equal(unsupported.ok, false);

  const joined = joinDevRoom(JOINER, "Joiner", 3, 5_000);
  assert.equal(joined.ok, true);
  if (!joined.ok) return;
  assert.equal(joined.room.status, "waiting");
  assert.equal(joined.room.current_players, 2);
  setDevPlayerSide(HOST, "USA");
  setDevPlayerSide(JOINER, "GERMANY");
  const room = listDevRooms(5_000).find((entry) => entry.room_number === 3);
  assert.deepEqual(room?.players.map((player) => [player.display_name, player.side, player.connected]), [
    ["Host", "USA", true],
    ["Joiner", "GERMANY", true],
  ]);

  const again = joinDevRoom(JOINER, "Joiner", 3, 5_100);
  assert.equal(again.ok, true);
  if (!again.ok) return;
  assert.equal(again.room.current_players, 2);
});

test("a disconnected player stays on an active roster and leaves a waiting seat", () => {
  clearDevLobbyState();
  assert.equal(hostRoom().ok, true);
  const joined = joinDevRoom(JOINER, "Guest 2222", 1, 8_000);
  assert.equal(joined.ok, true);
  if (!joined.ok) return;
  assert.equal(joined.room.status, "in_progress");
  setDevPlayerSide(JOINER, "GERMANY");
  setDevPlayerConnected(JOINER, false);
  const active = listDevRooms(8_000).find((entry) => entry.room_number === 1);
  assert.equal(active?.status, "in_progress");
  assert.equal(active?.players.find((player) => player.id === JOINER)?.connected, false);
  assert.equal(active?.players.find((player) => player.id === JOINER)?.side, "GERMANY");

  clearDevLobbyState();
  const waiting = hostDevRoom({
    devGuestId: HOST,
    displayName: "Host",
    roomNumber: 2,
    matchName: "Open",
    mapId: "grand_battle",
    teamSize: 5,
    matchLengthSec: 900,
    serverUrl: "ws://127.0.0.1:3000",
  }, 9_000);
  assert.equal(waiting.ok, true);
  assert.equal(joinDevRoom(JOINER, "Guest 2222", 2, 9_000).ok, true);
  const after = listDevRooms(9_000 + 31_000).find((entry) => entry.room_number === 2);
  assert.equal(after?.players.some((player) => player.id === JOINER), false);
  assert.equal(after?.players.some((player) => player.id === HOST), true);
});
