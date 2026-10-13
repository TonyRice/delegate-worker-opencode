#!/usr/bin/env python3
"""
filter-subagent-stream.py
Streaming JSON event filter for headless OpenCode runs.

- Reads newline-delimited JSON events from stdin (opencode run --format json).
- Simultaneously writes full raw JSON stream to a session JSONL archive file.
- Discards heavy tool payloads (raw file reads, command output dumps, metadata).
- If --progress is enabled: prints compact 1-line tool execution breadcrumbs to stderr.
- Enforces a safety character cap on the final assistant response to protect context windows.
- Emits a structured Executive Summary block to stdout upon completion.
"""

import sys
import os
import json
import argparse
from datetime import datetime

def format_tool_crumb(tool_name, input_data):
    """Formats a concise 1-line tool breadcrumb."""
    if not isinstance(input_data, dict):
        return f"→ [{tool_name}]"
    
    target = ""
    if "path" in input_data:
        target = str(input_data["path"])
    elif "filePath" in input_data:
        target = str(input_data["filePath"])
    elif "command" in input_data:
        cmd = str(input_data["command"]).strip()
        target = cmd if len(cmd) <= 60 else cmd[:57] + "..."
    elif "pattern" in input_data:
        target = str(input_data["pattern"])
    elif "query" in input_data:
        target = str(input_data["query"])
    elif input_data:
        first_val = str(next(iter(input_data.values())))
        target = first_val if len(first_val) <= 40 else first_val[:37] + "..."

    return f"→ [{tool_name}] {target}".strip()

def main():
    parser = argparse.ArgumentParser(description="Filter OpenCode JSON stream for minimal agent context")
    parser.add_argument("--session", required=True, help="Session ID")
    parser.add_argument("--mode", default="build", help="Task mode (discover, build, continue)")
    parser.add_argument("--model", default="", help="Model name")
    parser.add_argument("--progress", action="store_true", help="Print 1-line tool breadcrumbs to stderr")
    parser.add_argument("--max-chars", type=int, default=5000, help="Max characters for the final report")
    parser.add_argument("--archive-dir", default="", help="Directory to save session raw logs and archives")
    args = parser.parse_args()

    session_id = args.session
    task_mode = args.mode
    model_name = args.model
    show_progress = args.progress
    max_chars = args.max_chars

    # Setup archive directory
    archive_dir = args.archive_dir
    if not archive_dir:
        # Default fallback relative to current working directory
        archive_dir = os.path.join(os.getcwd(), ".agents", "opencode", "sessions")
    os.makedirs(archive_dir, exist_ok=True)

    jsonl_log_path = os.path.join(archive_dir, f"{session_id}.jsonl")
    jsonl_file = open(jsonl_log_path, "a", encoding="utf-8")

    total_cost = 0.0
    total_input_tokens = 0
    total_output_tokens = 0
    total_cache_read = 0
    total_reasoning = 0
    tool_calls_count = 0

    # Store text parts grouped by messageID/partID
    messages_order = []
    messages_text = {}
    current_part_id = None

    try:
        for line in sys.stdin:
            line_str = line.strip()
            if not line_str:
                continue

            # 1. Lossless append to session JSONL
            jsonl_file.write(line_str + "\n")
            jsonl_file.flush()

            try:
                event = json.loads(line_str)
            except json.JSONDecodeError:
                continue

            event_type = event.get("type")
            part = event.get("part", {})

            # 2. Extract metrics from step_finish
            if event_type == "step_finish":
                total_cost += part.get("cost", 0.0)
                tokens = part.get("tokens", {})
                total_input_tokens += tokens.get("input", 0)
                total_output_tokens += tokens.get("output", 0)
                total_reasoning += tokens.get("reasoning", 0)
                total_cache_read += tokens.get("cache", {}).get("read", 0)

            # 3. Handle tool calls
            elif event_type == "tool_use":
                tool_calls_count += 1
                if show_progress:
                    tool_name = part.get("tool", "tool")
                    state = part.get("state", {})
                    input_data = state.get("input", {})
                    crumb = format_tool_crumb(tool_name, input_data)
                    print(crumb, file=sys.stderr, flush=True)

            # 4. Handle text responses
            elif event_type == "text":
                part_id = part.get("id") or str(event.get("timestamp"))
                text_content = part.get("text", "")
                if part_id not in messages_text:
                    messages_order.append(part_id)
                messages_text[part_id] = text_content

    finally:
        jsonl_file.close()

    # Determine final assistant report
    final_report = ""
    if messages_order:
        # Get the latest message
        final_report = messages_text.get(messages_order[-1], "").strip()
        # If the latest is empty or trivial, check second to last
        if not final_report and len(messages_order) > 1:
            final_report = messages_text.get(messages_order[-2], "").strip()

    if not final_report:
        final_report = "(Subagent completed with no final text message.)"

    # Apply Safety Catch on output size
    truncated = False
    if len(final_report) > max_chars:
        truncated = True
        final_report = final_report[:max_chars].rstrip() + (
            f"\n\n... [OUTPUT TRUNCATED: Exceeded safety limit of {max_chars:,} characters. "
            f"Full raw response preserved in {jsonl_log_path}]"
        )

    # Print Executive Summary to stdout
    print("\n" + "=" * 65)
    print(f" DELEGATE SUBAGENT SUMMARY ({task_mode.upper()})")
    print("=" * 65)
    print(f"• Session ID:   {session_id}")
    if model_name:
        print(f"• Model:        {model_name}")
    print(f"• Total Cost:   ${total_cost:.6f}")
    print(f"• Token Usage:  In: {total_input_tokens:,} | Cache Read: {total_cache_read:,} | Out: {total_output_tokens:,}")
    if tool_calls_count > 0:
        print(f"• Tool Calls:   {tool_calls_count} action(s) performed")
    print("-" * 65)
    print("Subagent Report:")
    print(final_report)
    print("-" * 65)
    print(f"• Raw Log:      {jsonl_log_path}")
    print("=" * 65 + "\n")

if __name__ == "__main__":
    main()
