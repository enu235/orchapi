# Orchapi Client Skill

Thin wrapper around the orchapi REST API (`http://127.0.0.1:7878` by default).

**Script:** `.claude/skills/orchapi-client/client.py` (shared with the Claude Code driver)

## Usage

```bash
python3 .claude/skills/orchapi-client/client.py list-profiles
python3 .claude/skills/orchapi-client/client.py get-profile <name>
python3 .claude/skills/orchapi-client/client.py create-session --spec '<json>'
python3 .claude/skills/orchapi-client/client.py count-running
python3 .claude/skills/orchapi-client/client.py list-sessions --status running --limit 20
python3 .claude/skills/orchapi-client/client.py get-session <session-id>
```

For full command reference, see `.claude/skills/orchapi-client/SKILL.md`.
