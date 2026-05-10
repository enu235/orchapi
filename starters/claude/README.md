# Claude Code starter environment

This directory is a minimal Claude Code workspace for orchapi child sessions. Copy it into your project and point a route at it.

## Setup

```bash
# 1. Copy the starter into your project
cp -r /path/to/orchapi/starters/claude ~/dev/my-project

# 2. Add a route in driver/config/routes.toml
```

```toml
[[routes]]
list       = "Coding"
profile    = "default"          # must have agent = "claude" in profiles/default.toml
cwd        = "/Users/you/dev/my-project"
```

```bash
# 3. Optionally customise .claude/CLAUDE.md with project-specific context
#    (tech stack, conventions, file layout, etc.)
```

## Customising

- **`.claude/CLAUDE.md`** — add project context: language, framework, test commands, coding style. The more context here, the better the agent performs.
- **`.claude/settings.json`** — adjust `allow`/`deny` tool permissions. See [Claude Code permissions docs](https://docs.anthropic.com/en/docs/claude-code/settings) for options.

## How it works

When orchapi dispatches a session to this `cwd`, Claude Code is invoked with the task's `action_prompt`. Claude reads `.claude/CLAUDE.md` for context, does the work, and exits. The orchapi writeback worker then PATCHes Microsoft To-Do with the outcome.

## See also

- [orchapi executor docs](../../docs/executors/claude.md)
- [Routing rules](../../docs/driver-router.md)
- [Profiles reference](../../docs/profiles.md)
