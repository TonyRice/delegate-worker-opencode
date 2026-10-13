# Delegate Worker (OpenCode)

A headless [OpenCode](https://opencode.ai) subagent orchestrator, skill, and scope guard protocol for Antigravity and AI coding assistants.

Protect your main chat token context and budget runway by offloading repetitive file discovery, boilerplate generation, deep diffs, and verification test suites to an autonomous headless OpenCode worker.

---

## Architecture & Features

- 🛡️ **Scope Guard (`validate-workorder-scope.py`)**: Strict pre/post git tree validation guaranteeing that subagents only touch files explicitly authorized in the work order.
- ⚡ **Token Guard (`filter-subagent-stream.py`)**: Real-time streaming JSON filter that suppresses verbose tool dumps, protects context windows with a safety length cap, and emits a structured Executive Summary.
- 🔍 **Discovery Mode (`discover`)**: Offloads code exploration, call hierarchy tracing, and architectural queries into isolated subagent sessions without polluting main context.
- 📦 **Structured Work Orders (`init` / `build`)**: Enforces clean contracts, target files, behavioral invariants, and verification commands.
- 📝 **Automatic Session Archival (`archive-subagent-session.py`)**: Exports full session transcripts, costs, token usage, tool calls, and findings into markdown summaries.

---

## Directory Structure

```text
delegate-worker-opencode/
├── plugin.json                              # Antigravity plugin manifest
├── agents/
│   └── delegate-worker/
│       └── agent.md                         # Delegate Worker agent definition
├── skills/
│   └── delegate-worker/
│       ├── SKILL.md                         # Protocol definition and activation
│       └── scripts/
│           ├── run-subagent.sh              # Unified CLI wrapper
│           ├── filter-subagent-stream.py    # Streaming JSON filter & token guard
│           ├── validate-workorder-scope.py  # Git working tree scope guard
│           └── archive-subagent-session.py  # Session transcript and metrics exporter
├── bin/
│   └── install.sh                           # Quick installer into projects
└── README.md
```

---

## Prerequisites

1. **OpenCode CLI**: Ensure `opencode` is installed and authenticated.
   - Checked automatically in `~/.opencode/bin/opencode`, `/usr/local/bin/opencode`, or `PATH`.
2. **Python 3**: For Scope Guard and session archiving.
3. **Git**: Used for scope tracking and repository root discovery.

---

## Installation

### Option 1: Copy into your project's `.agents/` directory
From your project's root:
```bash
git clone git@github.com:TonyRice/delegate-worker-opencode.git /tmp/delegate-worker
/tmp/delegate-worker/bin/install.sh .agents
```

### Option 2: Add as a Git Submodule
```bash
git submodule add git@github.com:TonyRice/delegate-worker-opencode.git .agents/plugins/delegate-worker
```

### Option 3: Global Antigravity CLI Installation
To install the skill globally across all projects on your machine (installs into `~/.gemini/antigravity-cli/skills/` by default):
```bash
./install.sh
```


---

## Usage Workflow

### 1. Discovery Mode
When you need to explore code without dumping dozens of files into your chat window:
```bash
.agents/skills/delegate-worker/scripts/run-subagent.sh discover "Find all implementations of Router and trace dispatch pipeline"
```
Findings are printed and saved to `.agents/discovery/`.

### 2. Create a Work Order
Generate a standardized task specification:
```bash
.agents/skills/delegate-worker/scripts/run-subagent.sh init add-auth-middleware
```
Edit the generated `.agents/workorders/add-auth-middleware.md`:
```markdown
# Work Order: add-auth-middleware

## 1. Objective
Add JWT validation middleware to all incoming HTTP request handlers.

## 2. Target Files
- Modify: `src/server/router.ts`
- Create: `test/server/auth-middleware.test.ts`

## 3. Implementation Contract
- Verify bearer token in Authorization header.
- Return HTTP 401 if missing or invalid.

## 4. Verification Command
`npm test -t auth-middleware`
```

### 3. Build & Enforce Scope
Dispatch the task to OpenCode:
```bash
.agents/skills/delegate-worker/scripts/run-subagent.sh build .agents/workorders/add-auth-middleware.md
```
The runner pipes OpenCode through the Token Guard filter (`filter-subagent-stream.py`), suppressing intermediate tool noise, enforcing the 5,000-character safety cap, and presenting a structured Executive Summary alongside Scope Guard validation and git diff statistics.

#### Execution Flags & Options
- **Default (Silent)**: Zero live output while running; prints only the final Executive Summary.
- **`--progress` (or `PROGRESS=1`)**: Streams single-line tool breadcrumbs (`→ [read] src/file.ts`) without tool outputs.
- **`--verbose` (or `VERBOSE=1`)**: Bypasses filtering and streams full raw logs.
- **`--max-chars <N>`**: Customizes the safety response length limit (default: `5000` chars).

---

## License

This project is dedicated to the public domain under the [CC0 1.0 Universal](LICENSE) (CC0 1.0) Public Domain Dedication. You can copy, modify, distribute, and perform the work, even for commercial purposes, all without asking permission.
