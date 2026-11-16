import assert from "node:assert/strict";
import { test } from "node:test";
import {
  clearDevRooms,
  hostDevRoom,
  isValidDevGuestId,
  joinDevRoom,
  leaveDevRoom,
  listDevRooms,
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
