---
name: delegate-worker
description: >-
  Subagent worker delegation protocol. Use this skill when offloading code discovery,
  investigation, multi-line implementation, boilerplate generation, or test suite creation
  to the headless OpenCode subagent via .agents/skills/delegate-worker/scripts/run-subagent.sh.
---

# Subagent Worker Delegation Protocol

You are the Lead Architect and QA Lead. Your primary directive is to protect token context and budget runway by offloading repetitive file discovery, boilerplate generation, deep diffs, and unit testing to the headless OpenCode subagent.

## Rules of Engagement

### 1. Direct Coding vs. Delegation
- **Delegate by Default:** Any multi-line implementation, new method, new class, test suite, or cross-file refactor MUST be delegated to OpenCode via `.agents/skills/delegate-worker/scripts/run-subagent.sh`.
- **Pre-flight & Binary Location:** Do NOT manually search the filesystem or test for `opencode` with `which`, `whereis`, or `find`. `run-subagent.sh` handles all PATH and binary resolution automatically.
- **Direct Coding Allowed ONLY When:**
  1. The user explicitly requests you to write the code directly.
  2. The edit is surgical and trivial (e.g., modifying an existing single-line config value, fixing a minor typo in a comment, or toggling a boolean flag) where creating a work order and spawning an external process introduces unreasonable overhead.

### 2. Phase 1: Context Isolation & Discovery (`discover` or `continue`)
- Do NOT run broad `cat`, `grep`, or dump entire files into this chat session to understand existing code.
- Instead, invoke OpenCode in discovery mode:
  ```bash
  .agents/skills/delegate-worker/scripts/run-subagent.sh discover "<precise query: trace call hierarchy, list method signatures, find usages>" [model]
  ```
- **Isolated Sessions:** Each discovery run is assigned an isolated session ID (`ses_<epoch>_<hex>`).
- **Discovery Storage:** Findings are automatically saved to `.agents/discovery/<timestamp>_<topic>.md` and archived under `.agents/opencode/sessions/`.
- **Follow-up Clarifications:** If a discovery answer requires follow-up without re-reading all files, use:
  ```bash
  .agents/skills/delegate-worker/scripts/run-subagent.sh continue <session_id> "<follow-up question>"
  ```

### 3. Phase 2: Formulating the Work Order (`build`)
Never send loose, conversational prompts into build mode.
1. Generate a new work order skeleton:
   ```bash
   .agents/skills/delegate-worker/scripts/run-subagent.sh init <task-name>
   ```
2. Populate the structured Markdown file at `.agents/workorders/<task-name>.md`:

```markdown
# Work Order: <Task Name>

## 1. Objective
<One to two sentences stating the exact functional requirement.>

## 2. Target Files
- Modify: `path/to/target-file.ext`
- Create: `path/to/test-file.ext`

## 3. Implementation Contract
- **Classes / Functions:** <Exact names, parameters, return types, and throws clauses>
- **Behavioral Invariants:** <Critical edge cases, nullability, validation rules>
- **Error Handling:** <Specific exception types to throw or catch>

## 4. Verification Command
`<exact shell command to verify: e.g. npm test or ./mvnw test -Dtest=MyTest>`
```

### 4. Phase 3: Execution & Scope Enforcement
Execute the work order via:

```bash
.agents/skills/delegate-worker/scripts/run-subagent.sh build ".agents/workorders/<task-name>.md" [model]
```

- **Minimal Streaming Logs (Token Guard):** By default, subagent executions are piped through `filter-subagent-stream.py`, discarding raw file dumps and tool payloads to protect your token context.
- **Output Modes:**
  - *Default (Silent)*: Emits only the compact Executive Summary upon completion.
  - *`--progress` (or `PROGRESS=1`)*: Streams lightweight 1-line tool breadcrumbs (`→ [read] file.ts`) without payloads.
  - *`--verbose` (or `VERBOSE=1`)*: Bypasses filtering for raw debug output.
- **Safety Catch:** Automatically caps the printed subagent report (default: 5,000 characters) to prevent runaway responses from blowing context. Full untruncated responses are always preserved on disk.
- **Scope Guard (`validate-workorder-scope.py`):** Snapshots the git tree and enforces that **only** files declared under `## 2. Target Files` were created or modified.
- **Model Tiers:**
  - Standard workhorse: `opencode-go/deepseek-v4.1-flash` (default)
  - Complex architectural refactors or intricate concurrency/type logic: `opencode-go/deepseek-v4-pro`

### 5. Phase 4: Review & Verification
1. **Review Executive Summary:** Read the `Subagent Report` printed in the terminal summary block. The subagent summarizes its implementation actions and test results directly.
2. **Verify Scope & Diffs:** Confirm Scope Guard passed and check the compact `git diff --stat`.
3. **Deep Inspection (If Needed):** Check `.agents/opencode/sessions/<id>.md` or raw `.jsonl` log only if detailed post-mortem debugging is required.

### 6. Error Escalation Protocol
If the runner script returns a non-zero exit code or Scope Guard flags an unauthorized file:
1. Immediately **HALT** all automated actions.
2. Do **NOT** attempt unguided automated retries or rewrite the code yourself.
3. Report the exact exit code and stderr output directly to the user.
4. Present clear options for how to proceed (e.g., adjust work order spec, change model tier, or inspect local environment).
