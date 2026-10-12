# Delegate Worker (OpenCode)

A headless [OpenCode](https://opencode.ai) subagent orchestrator, skill, and scope guard protocol for Antigravity and AI coding assistants.

Protect your main chat token context and budget runway by offloading repetitive file discovery, boilerplate generation, deep diffs, and verification test suites to an autonomous headless OpenCode worker.

---

## Architecture & Features

- 🛡️ **Scope Guard (`validate-workorder-scope.py`)**: Strict pre/post git tree validation guaranteeing that subagents only touch files explicitly authorized in the work order.
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

### Option 3: Global Antigravity Customization
To make the skill and agent available across all projects on your machine:
```bash
./bin/install.sh ~/.gemini/config
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
The runner will snapshot the git tree, run OpenCode, enforce that *only* the declared target files were modified, and report any scope violations before presenting the diff.

---

## License

MPL-2.0 or MIT. Created by Tony Rice.
