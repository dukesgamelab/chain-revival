# Chain Revival — Claude Code Rules

## Git

- **No Claude attribution.** Never add `Co-Authored-By: Claude` or any Claude/Anthropic attribution lines to commit messages or PR descriptions. All commits must appear as authored solely by `dukesgamelab`.
- Squash multiple commits into one clean commit per phase or feature before pushing.
- Never amend a pushed commit — make a new commit instead.
- All work is on the `multiplayer-complete` branch.

## Deployment

After every commit, push and deploy automatically:
1. `git push origin multiplayer-complete`
2. If server changes: `fly deploy -a chain-revival-ax0q1g --remote-only`
3. If new SQL migration: tell Richard to run it in Supabase SQL Editor
4. Verify with `fly status` / `fly logs` if needed
