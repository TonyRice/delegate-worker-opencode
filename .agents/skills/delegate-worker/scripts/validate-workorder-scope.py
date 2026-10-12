#!/usr/bin/env python3
import sys
import os
import re
import subprocess

def main():
    if len(sys.argv) < 3:
        print("Usage: validate-workorder-scope.py <workorder_file> <pre_status_file>", file=sys.stderr)
        sys.exit(1)

    workorder_file = sys.argv[1]
    pre_status_file = sys.argv[2]

    if not os.path.isfile(workorder_file):
        print(f"Scope Guard: Input is not a workorder file ({workorder_file}). Skipping target file check.")
        return

    # Parse target files from workorder
    with open(workorder_file, "r", encoding="utf-8") as f:
        content = f.read()

    targets = set()
    in_target_section = False
    for line in content.splitlines():
        line_clean = line.strip()
        if "## 2. Target Files" in line_clean or "## Target Files" in line_clean:
            in_target_section = True
            continue
        elif line_clean.startswith("## ") and in_target_section:
            break

        if in_target_section and line_clean.startswith("-"):
            found = re.findall(r"`([^`]+)`", line_clean)
            for item in found:
                # normalize path relative to repo root
                norm = os.path.normpath(item.strip())
                targets.add(norm)

    if not targets:
        print("Scope Guard Warning: No target files declared under '## 2. Target Files'. Skipping strict check.")
        return

    # Read pre-status modified files
    pre_modified = set()
    if os.path.isfile(pre_status_file):
        with open(pre_status_file, "r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split(None, 1)
                if len(parts) == 2:
                    pre_modified.add(os.path.normpath(parts[1]))

    # Get current status
    proc = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
    current_modified = set()
    for line in proc.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            current_modified.add(os.path.normpath(parts[1]))

    # Changed specifically by this subagent run
    newly_modified = current_modified - pre_modified

    # Exclude internal ignored directories if any leaked into status
    leaked_candidates = {
        f for f in newly_modified
        if not f.startswith(".agents/") and not f.startswith(".antigravity/")
    }

    # Verify every newly modified file is in declared targets
    violations = []
    for f in leaked_candidates:
        if f not in targets:
            violations.append(f)

    if violations:
        print("\n=======================================================", file=sys.stderr)
        print("❌ SCOPE GUARD VIOLATION DETECTED", file=sys.stderr)
        print("The subagent modified files NOT declared in the work order:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        print("\nDeclared Target Files were:", file=sys.stderr)
        for t in sorted(targets):
            print(f"  + {t}", file=sys.stderr)
        print("=======================================================\n", file=sys.stderr)
        sys.exit(2)
    else:
        print(f"✅ Scope Guard: All {len(leaked_candidates)} modified file(s) match declared targets.")

if __name__ == "__main__":
    main()
