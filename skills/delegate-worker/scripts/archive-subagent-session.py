#!/usr/bin/env python3
import sys
import os
import json
import subprocess
from datetime import datetime

def find_repo_root(start_dir):
    # Try git rev-parse first
    try:
        proc = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, cwd=start_dir)
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
    except Exception:
        pass

    # Walk up checking for .git or .agents
    curr = os.path.abspath(start_dir)
    while curr and curr != os.path.dirname(curr):
        if os.path.isdir(os.path.join(curr, ".git")) or os.path.isdir(os.path.join(curr, ".agents")):
            return curr
        curr = os.path.dirname(curr)
    
    # Fallback: 4 levels up
    return os.path.abspath(os.path.join(start_dir, "..", "..", "..", ".."))

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = find_repo_root(script_dir)
    sessions_dir = os.path.join(repo_root, ".agents", "opencode", "sessions")
    discovery_dir = os.path.join(repo_root, ".agents", "discovery")
    os.makedirs(sessions_dir, exist_ok=True)
    os.makedirs(discovery_dir, exist_ok=True)

    # Resolve opencode binary
    opencode_bin = os.environ.get("OPENCODE_BIN")
    if not opencode_bin:
        home_bin = os.path.expanduser("~/.opencode/bin/opencode")
        if os.path.isfile(home_bin) and os.access(home_bin, os.X_OK):
            opencode_bin = home_bin
        else:
            opencode_bin = subprocess.run(["which", "opencode"], capture_output=True, text=True).stdout.strip()

    if not opencode_bin:
        print("Warning: Could not locate opencode binary for archiving.", file=sys.stderr)
        return

    # If session_id is passed as first arg
    if len(sys.argv) >= 2 and sys.argv[1].strip():
        session_id = sys.argv[1].strip()
    else:
        proc = subprocess.run([opencode_bin, "session", "list"], capture_output=True, text=True)
        if proc.returncode != 0 or not proc.stdout.strip():
            print("Warning: No opencode sessions found to archive.", file=sys.stderr)
            return
        for line in proc.stdout.splitlines():
            line = line.strip()
            if line:
                session_id = line.split()[0]
                break
        else:
            return

    # Optional mode argument (discover / build)
    task_mode = sys.argv[2].strip() if len(sys.argv) >= 3 else "unknown"

    # Export session
    cmd = [opencode_bin, "session", "export", session_id]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"Warning: Failed to export session {session_id}: {proc.stderr}", file=sys.stderr)
        return

    raw_json = proc.stdout
    try:
        data = json.loads(raw_json)
    except json.JSONDecodeError as e:
        print(f"Warning: Failed to decode session JSON: {e}", file=sys.stderr)
        return

    info = data.get("info", {})
    created_ts = info.get("time", {}).get("created", 0) / 1000.0
    if created_ts > 0:
        dt = datetime.fromtimestamp(created_ts)
        timestamp_str = dt.strftime("%Y%m%d_%H%M%S")
    else:
        dt = datetime.now()
        timestamp_str = dt.strftime("%Y%m%d_%H%M%S")

    # Save raw export JSON
    raw_filename = f"{timestamp_str}_{session_id}.json"
    raw_path = os.path.join(sessions_dir, raw_filename)
    with open(raw_path, "w", encoding="utf-8") as f:
        f.write(raw_json)

    # Extract summary details
    title = info.get("title", "Untitled Session")
    agent = info.get("agent", "unknown")
    model_info = info.get("model", {})
    model_name = f"{model_info.get('providerID', '')}/{model_info.get('id', '')}"
    cost = info.get("cost", 0.0)
    tokens = info.get("tokens", {})
    inp = tokens.get("input", 0)
    out = tokens.get("output", 0)
    cache_read = tokens.get("cache", {}).get("read", 0)

    # Collect tool calls & final outputs
    tool_calls = []
    final_outputs = []

    for msg in data.get("messages", []):
        for c in msg.get("content", []):
            ctype = c.get("type")
            if ctype == "tool":
                tname = c.get("tool", "")
                tstate = c.get("state", {})
                tinput = tstate.get("input", {})
                tool_calls.append((tname, tinput))
            elif ctype == "text":
                text = c.get("text", "").strip()
                if text:
                    final_outputs.append(text)

    # Write Markdown summary
    summary_filename = f"{timestamp_str}_{session_id}.md"
    summary_path = os.path.join(sessions_dir, summary_filename)

    with open(summary_path, "w", encoding="utf-8") as f:
        f.write(f"# OpenCode Session Summary: {title}\n\n")
        f.write(f"- **Session ID:** `{session_id}`\n")
        f.write(f"- **Timestamp:** {dt.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"- **Agent Mode:** `{agent}`\n")
        f.write(f"- **Model:** `{model_name}`\n")
        f.write(f"- **Cost:** `${cost:.6f}`\n")
        f.write(f"- **Tokens:** Input: {inp:,} | Cache Read: {cache_read:,} | Output: {out:,}\n\n")

        if tool_calls:
            f.write("## Actions Taken\n")
            for tname, tinput in tool_calls:
                call_desc = f"- **Tool `{tname}`**" if tname else "- **Tool action**"
                f.write(f"{call_desc}: `{json.dumps(tinput)}`\n")
            f.write("\n")

        if final_outputs:
            f.write("## Agent Output / Findings\n\n")
            f.write(final_outputs[-1])
            f.write("\n")

    # If discover mode, also persist directly to .agents/discovery/
    if task_mode in ("discover", "explore", "plan") and final_outputs:
        clean_slug = "".join(c if c.isalnum() or c in ("-", "_") else "_" for c in title.lower())[:50].strip("_")
        if not clean_slug:
            clean_slug = session_id
        discovery_file = os.path.join(discovery_dir, f"{timestamp_str}_{clean_slug}.md")
        with open(discovery_file, "w", encoding="utf-8") as f:
            f.write(f"# Discovery: {title}\n\n")
            f.write(f"- **Session ID:** `{session_id}`\n")
            f.write(f"- **Date:** {dt.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"- **Model:** `{model_name}`\n\n")
            f.write(final_outputs[-1])
            f.write("\n")
        print(f"==> Discovery findings saved to: .agents/discovery/{os.path.basename(discovery_file)}")

    print(f"==> Session archived to: .agents/opencode/sessions/{summary_filename}")

if __name__ == "__main__":
    main()
