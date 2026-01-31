---
description: Convert existing tasks into actionable, dependency-ordered GitHub issues for the feature based on available design artifacts.
tools: ['github/github-mcp-server/issue_write']
scripts:
  sh: scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
  ps: scripts/powershell/check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. Run `{SCRIPT}` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. From the executed script, locate the tasks directory:
   - **TASKS_DIR** = FEATURE_DIR/tasks/
   - **TASKS_INDEX** = FEATURE_DIR/tasks/tasks.jsonl

3. Parse `tasks.jsonl` to get the task list:
   - Each line is a JSON object with: id, summary, file, status, parallel, depends_on
   - For additional details, read individual task files from TASKS_DIR

4. Get the Git remote by running:

```bash
git config --get remote.origin.url
```

> [!CAUTION]
> ONLY PROCEED TO NEXT STEPS IF THE REMOTE IS A GITHUB URL

5. For each task in tasks.jsonl, use the GitHub MCP server to create a new issue:
   - **Title**: `[Task ID]: [Summary]` (e.g., "T001: Create project structure")
   - **Body**: Include objective, file paths, and acceptance criteria from the individual task file
   - **Labels**: Add appropriate labels based on task phase (setup, foundational, user-story, polish)
   - **Dependencies**: Reference dependent task issues in the body

> [!CAUTION]
> UNDER NO CIRCUMSTANCES EVER CREATE ISSUES IN REPOSITORIES THAT DO NOT MATCH THE REMOTE URL
