# Claude Code executor

Claude Code is the default executor and provides the most complete feature support in orchapi. It is also the only executor that can serve as the **driver** (the agent that polls To-Do and dispatches sessions).

---

## Install

```bash
# macOS / Linux (official installer)
curl -fsSL https://claude.ai/install.sh | sh

# Or via npm
npm install -g @anthropic-ai/claude-code

# Verify
claude --version
```

Full instructions at [claude.ai/code](https://claude.ai/code).

---

## Authenticate

```bash
claude login
# Follow the browser prompt to sign in with your Anthropic account
```

---

## Using the starter environment

Copy `starters/claude/` into the project you want Claude to work in:

```bash
cp -r /path/to/orchapi/starters/claude ~/dev/my-project
```

Then point a route at it:

```toml
# driver/config/routes.toml
[[routes]]
list    = "Coding"
profile = "default"              # profiles/default.toml must have agent = "claude"
cwd     = "/Users/you/dev/my-project"
```

---

## Customising the starter

**`.claude/CLAUDE.md`** is the primary instruction file. Add:
- Tech stack and language version
- How to run tests (`npm test`, `pytest`, `cargo test`, etc.)
- Coding style conventions or lint rules
- File layout ("all API handlers are in `src/api/`")
- Any context that would help a new contributor understand the project

The more concrete context you provide, the better Claude performs on real tasks.

**`.claude/settings.json`** controls tool permissions. The starter allows all read/write/shell tools by default. Restrict with a `deny` list if needed:

```json
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Edit(*)", "Write(*)"],
    "deny": ["Bash(rm -rf *)"]
  }
}
```

---

## Profile options

Claude Code supports the most profile fields of any executor:

```toml
# profiles/claude-default.toml
agent          = "claude"
model          = "claude-opus-4-7"
system_prompt  = "You are a senior software engineer..."
max_turns      = 40

[overrides]
allowed_tools     = ["Bash", "Read", "Edit", "Write"]
disallowed_tools  = []
permission_mode   = "bypassPermissions"   # or "default", "acceptEdits"
max_budget_usd    = 2.00
```

See [docs/profiles.md](../profiles.md) for the full field reference and how profiles merge with per-request overrides.

---

## How orchapi invokes Claude Code

```
claude --print --verbose --output-format stream-json --include-partial-messages \
       --model <model> \
       --append-system-prompt <system_prompt> \
       --permission-mode <permission_mode> \
       -- <action_prompt>
```

The process is launched with its cwd set to the route's `cwd`. Session output is streamed to `.orchapi/logs/<date>/<session-id>.log` and the live dashboard.

---

## Gotchas

- **No MCP servers in the starter.** If your project needs MCP, configure them in `.claude/settings.json` under `mcpServers`.
- **Budget cap.** `max_budget_usd` halts the session if the cost limit is reached. Set it in the profile or leave unset for no limit.
- **`--cwd` vs working directory.** When orchapi sets `cwd` in the session spec, it sets the OS-level working directory of the spawned process — this is separate from Claude's `--cwd` flag. The starter's `.claude/CLAUDE.md` assumes it is the working directory.
