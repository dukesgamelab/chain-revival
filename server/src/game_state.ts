/**
 * Placeholder for authoritative multiplayer game state.
 * Godot GameState is not ported yet.
 */

export interface GameStateSnapshot {
  version: number;
}

export class GameState {
  private version = 0;

  getSnapshot(): GameStateSnapshot {
    return { version: this.version };
  }

  /** Reserved for future server-side state mutations. */
  tick(): void {
    this.version += 1;
  }
}
