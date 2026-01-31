---
description: "README for the tasks directory structure"
---

# Tasks: [FEATURE NAME]

**Input**: Design documents from `/specs/[###-feature-name]/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

## Directory Structure

```
tasks/
├── tasks.jsonl              # Task index (one JSON object per line)
├── T001-setup-project.md    # Individual task detail files
├── T002-init-framework.md
├── T010-create-user-model.md
└── ...
```

## File Formats

### tasks.jsonl

Each line is a JSON object containing task metadata:

```json
{"id":"T001","summary":"Create project structure","file":"T001-create-project.md","status":"pending","parallel":false,"depends_on":[]}
{"id":"T002","summary":"Setup database schema","file":"T002-setup-database.md","status":"pending","parallel":false,"depends_on":["T001"]}
{"id":"T010","summary":"Create User model","file":"T010-create-user-model.md","status":"pending","parallel":true,"depends_on":["T002"]}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Task ID (T001, T002, etc.) |
| `summary` | string | One-line description |
| `file` | string | Filename of detail file |
| `status` | string | `pending` or `done` |
| `parallel` | boolean | Can run in parallel with other tasks |
| `depends_on` | array | List of prerequisite task IDs |

### Individual Task Files (T###-slug.md)

Each task has a dedicated file with:

- **Frontmatter**: id, summary, status, depends_on (must match tasks.jsonl)
- **Previous Related Tasks**: Context from prerequisite tasks
- **Task Details**: Objective, file paths, implementation notes
- **References**: Links to spec sections, data model, contracts
- **Acceptance Criteria**: Checkable completion criteria

## Task Organization

Tasks are organized by phase:

1. **Phase 1: Setup** - Project initialization (no story labels)
2. **Phase 2: Foundational** - Blocking prerequisites (no story labels)
3. **Phase 3+: User Stories** - One phase per story (P1, P2, P3...)
4. **Final Phase: Polish** - Cross-cutting concerns

## Parallel Execution

Tasks marked with `"parallel": true` in the JSONL can run concurrently when:
- They modify different files
- Their dependencies are all satisfied
- They belong to the same phase

## Validation

Run the validation script to check consistency:

```bash
# Bash
./scripts/bash/validate-tasks.sh

# PowerShell
./scripts/powershell/validate-tasks.ps1
```

The validator checks:
- JSONL validity (each line is valid JSON)
- File references (each file in JSONL exists)
- No orphan files (no task files without JSONL entry)
- Frontmatter sync (task file metadata matches JSONL)
- Dependency validity (all depends_on refs exist, no cycles)
- Status coherence (done tasks have all dependencies done)

## Usage

1. **Generate tasks**: Run `/speckit.tasks` to create this structure
2. **Implement**: Run `/speckit.implement` to execute tasks in order
3. **Track progress**: Task status is updated in both JSONL and individual files
4. **Create issues**: Run `/speckit.taskstoissues` to convert to GitHub issues

## Notes

- Tests are OPTIONAL - only include if explicitly requested
- Each user story should be independently testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
