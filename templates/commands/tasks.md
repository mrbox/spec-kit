---
description: Generate an actionable task structure with JSONL index and individual task files based on available design artifacts.
handoffs:
  - label: Analyze For Consistency
    agent: speckit.analyze
    prompt: Run a project analysis for consistency
    send: true
  - label: Implement Project
    agent: speckit.implement
    prompt: Start the implementation in phases
    send: true
scripts:
  sh: scripts/bash/check-prerequisites.sh --json
  ps: scripts/powershell/check-prerequisites.ps1 -Json
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. **Setup**: Run `{SCRIPT}` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load design documents**: Read from FEATURE_DIR:
   - **Required**: plan.md (tech stack, libraries, structure), spec.md (user stories with priorities)
   - **Optional**: data-model.md (entities), contracts/ (API endpoints), research.md (decisions), quickstart.md (test scenarios)
   - Note: Not all projects have all documents. Generate tasks based on what's available.

3. **Execute task generation workflow**:
   - Load plan.md and extract tech stack, libraries, project structure
   - Load spec.md and extract user stories with their priorities (P1, P2, P3, etc.)
   - If data-model.md exists: Extract entities and map to user stories
   - If contracts/ exists: Map endpoints to user stories
   - If research.md exists: Extract decisions for setup tasks
   - Generate tasks organized by user story (see Task Generation Rules below)
   - Generate dependency graph showing user story completion order
   - Create parallel execution examples per user story
   - Validate task completeness (each user story has all needed tasks, independently testable)

4. **Create tasks directory structure**: In FEATURE_DIR, create:

   ```
   tasks/
   ├── README.md           # Copy from templates/tasks-template.md with feature name filled in
   ├── tasks.jsonl         # Task index (one JSON per line)
   ├── T001-slug.md        # Individual task files
   ├── T002-slug.md
   └── ...
   ```

5. **Generate tasks.jsonl**: Create a JSONL file (one JSON object per line) with all tasks:

   **Format (each line is a complete JSON object)**:
   ```json
   {"id":"T001","summary":"Create project structure per implementation plan","file":"T001-create-project.md","status":"pending","parallel":false,"depends_on":[]}
   {"id":"T002","summary":"Initialize framework with dependencies","file":"T002-init-framework.md","status":"pending","parallel":false,"depends_on":["T001"]}
   {"id":"T003","summary":"Configure linting and formatting","file":"T003-config-linting.md","status":"pending","parallel":true,"depends_on":["T001"]}
   ```

   **Fields**:
   | Field | Type | Description |
   |-------|------|-------------|
   | `id` | string | Task ID (T001, T002, etc.) in execution order |
   | `summary` | string | One-line description with file paths |
   | `file` | string | Filename of the individual task file |
   | `status` | string | Always `pending` when generated |
   | `parallel` | boolean | True if task can run in parallel (different files, no blocking deps) |
   | `depends_on` | array | List of task IDs that must complete first |

6. **Generate individual task files**: For each task, create `T###-slug.md` using this structure:

   ```markdown
   ---
   id: T###
   summary: [One-line description with file paths]
   status: pending
   depends_on: [T001, T002]
   ---

   # T###: [Task Title]

   ## Previous Related Tasks

   - **T001**: [What T001 provides that this task needs]
   - **T002**: [What T002 provides that this task needs]

   ## Task Details

   ### Objective
   [Clear statement of what this task accomplishes]

   ### File Paths
   - `path/to/file.ext` - [Create new | Modify]
   - `path/to/other.ext` - [Create new | Modify]

   ### Implementation Notes
   [Technical details, patterns, constraints]

   ## References

   - **spec.md**: Section X.X - [Section Name]
   - **data-model.md**: [Entity] definition
   - **contracts/**: [Contract file]

   ## Acceptance Criteria

   - [ ] [Criterion 1]
   - [ ] [Criterion 2]
   ```

7. **Report**: Output summary:
   - Path to generated tasks/ directory
   - Total task count
   - Task count per phase/user story
   - Parallel opportunities identified
   - Independent test criteria for each story
   - Suggested MVP scope (typically User Story 1)

Context for task generation: {ARGS}

The task files should be immediately executable - each task must be specific enough that an LLM can complete it without additional context.

## Task Generation Rules

**CRITICAL**: Tasks MUST be organized by user story to enable independent implementation and testing.

**Tests are OPTIONAL**: Only generate test tasks if explicitly requested in the feature specification or if user requests TDD approach.

### Task ID and File Naming

- **Task ID**: Sequential (T001, T002, T003...) in execution order
- **File slug**: Kebab-case summary of task (max 40 chars)
- **Examples**:
  - T001 "Create project structure" → `T001-create-project.md`
  - T010 "Create User model in src/models/user.py" → `T010-create-user-model.md`
  - T015 "Implement auth middleware" → `T015-impl-auth-middleware.md`

### Task Organization by Phase

1. **Phase 1: Setup** - Project initialization
   - Task IDs: T001-T009
   - No depends_on for first task
   - No user story references

2. **Phase 2: Foundational** - Blocking prerequisites
   - Task IDs: T010-T019 (adjust as needed)
   - Depends on Setup completion
   - MUST complete before any user story

3. **Phase 3+: User Stories** - One phase per story (P1, P2, P3...)
   - Task IDs: T020+ (grouped by story)
   - Each story depends on Foundational
   - Within story: Tests (if requested) → Models → Services → Endpoints

4. **Final Phase: Polish** - Cross-cutting concerns
   - Highest task IDs
   - Depends on all user stories

### Parallel Task Rules

Set `"parallel": true` when:
- Task modifies different files than concurrent tasks
- All dependencies are already satisfied
- No data or state sharing with concurrent tasks

### Dependency Rules

- Every task (except T001) must have at least one dependency
- Dependencies must reference existing task IDs
- No circular dependencies allowed
- Foundational tasks block all user story tasks
- Within a story: models before services, services before endpoints

### Summary Format

The `summary` field should be:
- One line, max 80 characters
- Include target file path when applicable
- Use active voice ("Create", "Implement", "Configure")

**Examples**:
- `"Create project structure per implementation plan"`
- `"Initialize Python project with FastAPI dependencies"`
- `"Create User model in src/models/user.py"`
- `"Implement UserService in src/services/user_service.py"`

## Validation Before Completion

Before finalizing, verify:
1. Every task has a unique ID
2. Every task has a matching individual file
3. tasks.jsonl has valid JSON on each line
4. All depends_on references exist
5. No circular dependencies
6. Each user story has complete task coverage
7. Frontmatter in task files matches JSONL entries
