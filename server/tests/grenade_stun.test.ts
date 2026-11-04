import assert from "node:assert/strict";
import { test } from "node:test";
import { GRENADE_STUN_MIN_SEC, stunDurationAtDistance } from "../src/grenade_system";

test("grenade stun is at least 5s anywhere in the blast", () => {
  assert.equal(GRENADE_STUN_MIN_SEC, 5.0);
  assert.equal(stunDurationAtDistance(0), 6.0);
  assert.equal(stunDurationAtDistance(1), 5.0);
  assert.equal(stunDurationAtDistance(2), 5.0);
});
