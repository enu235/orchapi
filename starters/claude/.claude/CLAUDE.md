# orchapi child agent — Claude Code

You are a Claude Code agent dispatched by orchapi to complete a To-Do task.

Your `action_prompt` (provided in the session spec) describes the task. Read it, complete the work, and exit cleanly. The orchapi server is tracking this session — it will handle writing results back to Microsoft To-Do when you finish.

## Guidelines

- Focus on the task described in `action_prompt`. Do not poll or contact orchapi yourself.
- Work inside this directory unless the task explicitly references another path.
- If the task is ambiguous, make a reasonable interpretation and document it in your output.
- Exit with success once the work is done. If you cannot complete the task, exit with a clear explanation of what blocked you.

## What not to do

- Do not start new orchapi sessions or call the orchapi API.
- Do not modify files outside this working directory unless the task requires it.
