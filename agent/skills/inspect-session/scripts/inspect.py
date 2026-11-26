#!/usr/bin/env python3
"""inspect.py - Multi-agent conversation transcript inspector and audit tool.

Supports:
- Claude Code session JSONL files (~/.claude/projects/.../*.jsonl)
- Antigravity / Gemini CLI transcript JSONL files (~/.gemini/.../transcript.jsonl)
- MiniMax Code session JSONL files (~/.minimax/v2/sessions/.../messages.jsonl)
- CodeBuddy CLI session JSONL files (<session-id>.jsonl under ~/.codebuddy/)

Capabilities:
- Audit Git operations (commits, push, diff, branch, status)
- Audit File modifications (Write, Edit, Patch) with line and diff context
- Reconstruct DAG branch topology and trace specific branch lineages
- Compare divergent branches (--diff-branches A B)
- Chronological timeline inspection (--timeline)
- Filter failed commands and tool errors (--errors)
- Full-text keyword search (--search / --grep)
- Export to structured Markdown or JSON
"""

import argparse
import codecs
import html
import json
import os
import re
import signal
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# Handle broken pipes gracefully when piped to head/tail/less
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):
    pass


# The views print status markers (check mark, cross, emoji role labels) that
# a legacy console code page cannot encode. On a Chinese Windows console the
# piped stdout is GBK, and the first marker killed the run with
# UnicodeEncodeError. PYTHONIOENCODING is no fix: `python -I` ignores every
# PYTHON* variable. So stdout/stderr get an error handler that turns each
# marker into an ASCII stand-in (keeping ok/failed distinguishable) and any
# other unencodable character into '?'. A UTF-8 stream never calls it.
_ASCII_MARKERS = {
    "\u2713": "[ok]",  # check mark
    "\u274c": "[X]",  # cross mark
    "\u25a0": "#",  # black square, summary bars
    "\u2014": "--",  # em dash
    "\U0001f4c4": "*",  # page, file heading
    "\U0001f527": "-",  # wrench, tool call
    "\U0001f9d1": "",  # person, USER label
    "\U0001f916": "",  # robot, ASSISTANT label
    "\u2699": "",  # gear, SYSTEM label
    "\ufe0f": "",  # emoji presentation selector
    "\U0001f331": "",  # seedling, fork point
    "\U0001f33f": "",  # herb, branch A
    "\U0001f342": "",  # leaf, branch B
}


def _ascii_marker_fallback(exc):
    if not isinstance(exc, UnicodeEncodeError):
        raise exc
    chunk = exc.object[exc.start:exc.end]
    return "".join(_ASCII_MARKERS.get(ch, "?") for ch in chunk), exc.end


codecs.register_error("inspect_ascii_markers", _ascii_marker_fallback)


def make_output_safe():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="inspect_ascii_markers")
        except (AttributeError, ValueError, LookupError):
            pass


def stdout_is_unicode() -> bool:
    enc = getattr(sys.stdout, "encoding", None) or "ascii"
    try:
        return codecs.lookup(enc).name.startswith("utf-")
    except LookupError:
        return False


# Harnesses inject their own XML-ish blocks at the top of a user turn. The
# stored text keeps them (an audit wants to know what the agent was told),
# but the one-line preview must show what the user actually asked. CodeBuddy
# adds attributes (<system-reminder data-role="tool-hint">), hence [^>]*.
_NOISE_BLOCK_RE = re.compile(
    r"<(system-reminder|plugin-hook-context|agent-context|media-output-reminder"
    r"|mcode-tools-master-reminder)(?:\s[^>]*)?>.*?</\1>",
    re.S,
)


def preview_line(text: str, limit: int = 100) -> str:
    """First human-meaningful line of a message, harness noise removed."""
    if not text:
        return ""
    stripped = _NOISE_BLOCK_RE.sub("", text).strip()
    source = stripped or text.strip()
    for line in source.splitlines():
        s = line.strip()
        if s:
            return s[:limit]
    return source[:limit]


def format_timestamp(ts: Any) -> Optional[str]:
    """Render a transcript timestamp as a human-readable local time.

    Claude Code and Antigravity write ISO strings; MiniMax Code writes epoch
    milliseconds as an int. Anything unrecognised is passed through as-is.
    """
    if ts is None or ts == "":
        return None
    if isinstance(ts, bool):
        return str(ts)
    if isinstance(ts, (int, float)):
        seconds = ts / 1000.0 if abs(ts) > 1e11 else float(ts)
    elif isinstance(ts, str) and ts.strip().isdigit():
        seconds = int(ts.strip())
        seconds = seconds / 1000.0 if seconds > 1e11 else float(seconds)
    else:
        return str(ts)
    try:
        return datetime.fromtimestamp(seconds).strftime("%Y-%m-%d %H:%M:%S")
    except (ValueError, OSError, OverflowError):
        return str(ts)


class ToolRecord:
    def __init__(
        self,
        tool_id: str,
        name: str,
        category: str,
        summary: str,
        details: Dict[str, Any],
        is_error: bool = False,
        output: str = "",
        line_num: int = 0,
    ):
        self.tool_id = tool_id
        self.name = name
        self.category = category  # 'git', 'file_write', 'file_read', 'shell', 'web', 'other'
        self.summary = summary
        self.details = details
        self.is_error = is_error
        self.output = output
        self.line_num = line_num

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tool_id": self.tool_id,
            "name": self.name,
            "category": self.category,
            "summary": self.summary,
            "details": self.details,
            "is_error": self.is_error,
            "output_preview": self.output[:300] if self.output else "",
            "line_num": self.line_num,
        }


class TranscriptMessage:
    def __init__(
        self,
        index: int,
        role: str,
        text: str = "",
        uuid: Optional[str] = None,
        parent_uuid: Optional[str] = None,
        timestamp: Optional[str] = None,
        raw_obj: Optional[Dict[str, Any]] = None,
    ):
        self.index = index
        self.role = role  # 'user', 'assistant', 'system', 'meta'
        self.text = text
        self.uuid = uuid
        self.parent_uuid = parent_uuid
        self.timestamp = timestamp
        self.tools: List[ToolRecord] = []
        self.raw_obj = raw_obj or {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "index": self.index,
            "role": self.role,
            "uuid": self.uuid,
            "parent_uuid": self.parent_uuid,
            "timestamp": self.timestamp,
            "text": self.text,
            "tools": [t.to_dict() for t in self.tools],
        }


# Match git commands (handling subshells, cd ... && git ..., etc.)
_GIT_RE = re.compile(
    r"(?:^|[;&|\s])git(?:\s+-[A-Za-z0-9_-]+(?:\s+[^\s;&|]+)?)*\s+([a-z-]+)(.*?)(?=[;&|\n]|$)"
)
# GitHub CLI. Only real gh subcommands count, so prose such as "gh is"
# inside an echo is not mistaken for a GitHub operation.
_GH_SUBCOMMANDS = (
    "pr", "issue", "repo", "api", "run", "workflow", "release", "auth",
    "gist", "browse", "search", "label", "secret", "variable", "cache",
    "ruleset", "status", "project", "codespace", "ssh-key", "gpg-key",
    "extension", "alias", "config", "attestation",
)
_GH_RE = re.compile(
    r"(?:^|[;&|\s])gh\s+(" + "|".join(_GH_SUBCOMMANDS) + r")(?![\w-])(.*?)(?=[;&|\n]|$)"
)


def parse_git_command(cmd: str) -> Optional[Dict[str, Any]]:
    """Parse the first git or gh invocation out of a shell string."""
    if not cmd or ("git" not in cmd and "gh" not in cmd):
        return None
    found = []
    for tool, pattern in (("git", _GIT_RE), ("gh", _GH_RE)):
        m = pattern.search(cmd)
        if m:
            found.append((m.start(), tool, m))
    if not found:
        return None
    _, tool, match = min(found, key=lambda x: x[0])
    subcmd = match.group(1).strip()
    args = match.group(2).strip()
    return {
        "full_command": cmd.strip(),
        "tool": tool,
        "subcommand": subcmd,
        "args": args,
    }


def categorize_tool(
    name: str, args: Dict[str, Any], output: str = "", is_error: bool = False
) -> Tuple[str, str, Dict[str, Any]]:
    """Categorize tool and generate human-friendly summary."""
    category = "other"
    summary = name
    details: Dict[str, Any] = {}

    name_lower = name.lower()

    # Claude Code Bash / Gemini run_command
    if name_lower in ("bash", "run_command"):
        cmd = args.get("command") or args.get("CommandLine") or ""
        desc = args.get("description") or args.get("toolSummary") or ""
        details["command"] = cmd
        details["description"] = desc

        git_info = parse_git_command(cmd)
        if git_info:
            category = "git"
            tool = git_info["tool"]
            sub = git_info["subcommand"]
            sub_args = git_info["args"]
            summary = f"{tool} {sub}" + (f" {sub_args[:60]}" if sub_args else "")
            if tool != "git":
                details["git_tool"] = tool  # absent means plain git
            details["git_subcommand"] = sub
            details["git_args"] = sub_args
        else:
            category = "shell"
            first_line = cmd.strip().split("\n")[0]
            summary = first_line[:80] if first_line else desc[:80]

    # File writes / edits
    elif name_lower in ("write", "filewrite", "write_to_file"):
        category = "file_write"
        path = args.get("file_path") or args.get("path") or args.get("TargetFile") or ""
        content = args.get("content") or args.get("CodeContent") or ""
        details["file_path"] = path
        details["content_length"] = len(content)
        summary = f"Write {Path(path).name} ({len(content)} bytes)"

    elif name_lower in ("edit", "fileedit", "replace_file_content"):
        category = "file_write"
        path = args.get("file_path") or args.get("path") or args.get("TargetFile") or ""
        details["file_path"] = path
        old_s = args.get("old_string") or args.get("TargetContent") or ""
        new_s = args.get("new_string") or args.get("ReplacementContent") or ""
        details["old_lines"] = old_s.count("\n") + 1 if old_s else 0
        details["new_lines"] = new_s.count("\n") + 1 if new_s else 0
        summary = f"Edit {Path(path).name} (-{details['old_lines']}/+{details['new_lines']} lines)"

    # File reads
    elif name_lower in ("read", "fileread", "view_file"):
        category = "file_read"
        path = args.get("file_path") or args.get("path") or args.get("AbsolutePath") or ""
        details["file_path"] = path
        summary = f"Read {Path(path).name}"

    elif name_lower in ("grep", "glob", "ls"):
        category = "search"
        pattern = args.get("pattern") or args.get("path") or ""
        summary = f"{name} {pattern}"
        details["pattern"] = pattern

    elif "search" in name_lower or "web" in name_lower:
        category = "web"
        query = args.get("query") or args.get("url") or args.get("Url") or ""
        summary = f"Web {query[:60]}"
        details["query"] = query

    return category, summary, details


class TranscriptParser:
    def __init__(self, file_path: str):
        self.file_path = str(Path(file_path).resolve())
        self.source_path = self.file_path
        self.raw_records: List[Tuple[int, Dict[str, Any]]] = []
        self.format: str = "unknown"  # 'claude', 'gemini', 'minimax' or 'codebuddy'
        self.session_id: str = ""
        self.ai_title: str = ""
        self.models: Dict[str, int] = {}  # model -> assistant responses (CodeBuddy only)
        self.notes: List[str] = []
        self.messages: List[TranscriptMessage] = []
        self.uuid_to_msg: Dict[str, TranscriptMessage] = {}
        self.children: Dict[str, List[TranscriptMessage]] = defaultdict(list)
        self.branch_tips: List[Tuple[TranscriptMessage, int]] = []
        self.branch_points: List[Tuple[TranscriptMessage, List[TranscriptMessage]]] = []
        self._load_file()

    def _load_file(self):
        if not os.path.exists(self.file_path):
            raise FileNotFoundError(f"Transcript file not found: {self.file_path}")

        with open(self.file_path, "r", encoding="utf-8", errors="replace") as f:
            for idx, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    self.raw_records.append((idx, obj))
                except json.JSONDecodeError:
                    continue

        if not self.raw_records:
            return

        # A byte-range slice is not a transcript: rebuild it before parsing.
        self._reassemble_antigravity_chunks()

        # Detect format. Claude Code records carry a top-level "type"
        # ("user"/"assistant"/"summary"); MiniMax Code records carry
        # "message_id"/"turn_id" and a role of "toolResult"/"custom" that
        # Claude never writes. CodeBuddy also has a top-level "type" and an
        # "ai-title" record, so it must be claimed by its own markers before
        # the Claude fallback swallows it.
        first_objs = [r[1] for r in self.raw_records[:50]]
        if self._looks_like_codebuddy(first_objs):
            self.format = "codebuddy"
            self._parse_codebuddy()
        elif any("step_index" in o or o.get("source") in ("USER_EXPLICIT", "MODEL") for o in first_objs):
            self.format = "gemini"
            self._parse_gemini()
        elif any(
            ("message_id" in o and "turn_id" in o)
            or (
                isinstance(o.get("message"), dict)
                and o["message"].get("role") in ("toolResult", "custom")
            )
            for o in first_objs
        ):
            self.format = "minimax"
            self._parse_minimax()
        else:
            self.format = "claude"
            self._parse_claude()

        self._build_branch_indices()

    def _parse_claude(self):
        tool_results: Dict[str, Tuple[bool, str]] = {}

        # First pass: collect tool results and metadata
        for idx, obj in self.raw_records:
            t = obj.get("type")
            if t == "ai-title":
                self.ai_title = obj.get("aiTitle", "")
                self.session_id = obj.get("sessionId", "")
            elif t == "user":
                msg = obj.get("message", {})
                content = msg.get("content", [])
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            tid = b.get("tool_use_id", "")
                            is_err = b.get("is_error", False)
                            res_content = b.get("content", "")
                            if isinstance(res_content, list):
                                res_text = "".join(
                                    x.get("text", "") for x in res_content if isinstance(x, dict)
                                )
                            else:
                                res_text = str(res_content)
                            tool_results[tid] = (is_err, res_text)

        # Second pass: build messages and tool calls
        for idx, obj in self.raw_records:
            t = obj.get("type")
            if t not in ("user", "assistant", "system"):
                continue

            uuid = obj.get("uuid")
            parent_uuid = obj.get("parentUuid")
            ts = obj.get("timestamp")
            msg = obj.get("message", {})
            content = msg.get("content", "")

            text_parts = []
            tools: List[ToolRecord] = []

            if isinstance(content, str):
                text_parts.append(content)
            elif isinstance(content, list):
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    btype = b.get("type")
                    if btype == "text":
                        text_parts.append(b.get("text", ""))
                    elif btype == "thinking":
                        pass  # Skip raw CoT from display text
                    elif btype == "tool_use":
                        tid = b.get("id", "")
                        tname = b.get("name", "")
                        tinput = b.get("input", {}) or {}
                        is_err, tout = tool_results.get(tid, (False, ""))
                        cat, summ, det = categorize_tool(tname, tinput, tout, is_err)
                        tools.append(
                            ToolRecord(
                                tool_id=tid,
                                name=tname,
                                category=cat,
                                summary=summ,
                                details=det,
                                is_error=is_err,
                                output=tout,
                                line_num=idx,
                            )
                        )

            # Skip messages that are only tool_result responses without user prompt
            full_text = "\n".join(p for p in text_parts if p.strip()).strip()
            if t == "user" and not full_text and not tools:
                # This was likely just a tool_result holder
                continue

            tmsg = TranscriptMessage(
                index=idx,
                role=t,
                text=full_text,
                uuid=uuid,
                parent_uuid=parent_uuid,
                timestamp=ts,
                raw_obj=obj,
            )
            tmsg.tools = tools
            self.messages.append(tmsg)
            if uuid:
                self.uuid_to_msg[uuid] = tmsg

    def _reassemble_antigravity_chunks(self):
        """Antigravity also writes the transcript as byte-range slices under
        chunks/transcript/. A record can straddle a slice boundary, so a
        single chunk file is NOT a valid transcript -- parsing it alone
        silently drops the records cut in half. Reassemble the whole set."""
        p = Path(self.file_path)
        if p.parent.name != "transcript" or p.parent.parent.name != "chunks":
            return
        parts = sorted(p.parent.glob("*.jsonl"))
        if len(parts) < 2:
            return
        blobs = []
        for part in parts:
            try:
                with open(part, "r", encoding="utf-8", errors="replace") as f:
                    blobs.append(f.read())
            except OSError:
                return
        records: List[Dict[str, Any]] = []
        for line in "".join(blobs).splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        if len(records) <= len(self.raw_records):
            return
        self.raw_records = [(i, o) for i, o in enumerate(records, 1)]
        self.source_path = str(p.parent.parent.parent / "transcript.jsonl")
        self.notes.append(
            f"reassembled {len(parts)} chunk files into {len(records)} records"
        )

    def _antigravity_full_path(self) -> Optional[Path]:
        """Where the untruncated copy of this transcript lives."""
        p = Path(self.file_path)
        if p.parent.name == "transcript" and p.parent.parent.name == "chunks":
            candidate = p.parent.parent.parent / "transcript_full.jsonl"
        else:
            candidate = p.with_name("transcript_full.jsonl")
        return candidate if candidate.exists() else None

    def _merge_antigravity_full(self):
        """Antigravity writes a truncated transcript.jsonl next to an
        untruncated transcript_full.jsonl. Same records, same order; only the
        content of truncated records differs. Merge the full content in so a
        tool result is not silently cut off mid-output."""
        p = Path(self.file_path)
        full = self._antigravity_full_path()
        if full is None:
            return
        try:
            with open(full, "r", encoding="utf-8", errors="replace") as f:
                full_records = [json.loads(l) for l in f if l.strip()]
        except (OSError, ValueError):
            return
        if len(full_records) != len(self.raw_records):
            self.notes.append(
                f"transcript_full.jsonl has {len(full_records)} records, "
                f"transcript.jsonl has {len(self.raw_records)}; not merged"
            )
            return
        merged = 0
        for (_, obj), frec in zip(self.raw_records, full_records):
            if obj.get("step_index") != frec.get("step_index"):
                self.notes.append("transcript_full.jsonl is not aligned; not merged")
                return
            truncated = obj.get("truncated_fields") or []
            if not truncated:
                continue
            for key in truncated:
                if key in ("content", "tool_calls", "thinking") and frec.get(key) is not None:
                    obj[key] = frec[key]
                    merged += 1
            obj.pop("truncated_fields", None)
        if merged:
            self.notes.append(
                f"merged {merged} truncated field(s) from transcript_full.jsonl"
            )

    @staticmethod
    def _gemini_result_is_error(output: str, status: Optional[str]) -> bool:
        if status == "ERROR":
            return True
        m = re.search(r"exited with code\s+(-?\d+)", output)
        if m and m.group(1) != "0":
            return True
        return False

    @staticmethod
    def _gemini_user_text(text: str) -> str:
        """Antigravity wraps the prompt in <USER_REQUEST> plus a metadata
        block. Keep the request, drop the harness boilerplate."""
        m = re.search(r"<USER_REQUEST>(.*?)</USER_REQUEST>", text, re.S)
        return m.group(1).strip() if m else text

    def _parse_gemini(self):
        self._merge_antigravity_full()

        # Antigravity writes one PLANNER_RESPONSE record per batch of tool
        # calls and one GENERIC record per tool result, but the two streams
        # INTERLEAVE: in a two-call batch the first result can be written
        # before the call record itself. File order is therefore not causal
        # order -- the timestamps are. Pair on (created_at, file position) and
        # hand each result to the oldest call still waiting for one.
        ordered = sorted(
            range(len(self.raw_records)),
            key=lambda i: (self.raw_records[i][1].get("created_at") or "", i),
        )

        msg_by_line: Dict[int, TranscriptMessage] = {}
        pending: List[Tuple[int, str, Dict[str, Any], ToolRecord]] = []
        api_errors: List[Tuple[int, Optional[str], str]] = []

        for i in ordered:
            idx, obj = self.raw_records[i]
            source = obj.get("source")
            stype = obj.get("type")
            ts = obj.get("created_at")
            status = obj.get("status")
            content = obj.get("content") or ""
            tcs = obj.get("tool_calls") or []

            if stype == "ERROR_MESSAGE":
                api_errors.append(
                    (idx, ts, str(obj.get("error") or content or "unknown API error"))
                )
                continue

            role = "assistant" if source == "MODEL" else "user" if source in ("USER_EXPLICIT", "USER") else "system"
            if stype == "USER_INPUT":
                role = "user"

            # A GENERIC record from the model is a tool result: hand it to the
            # oldest call still waiting for one and fill that call in place.
            if stype == "GENERIC" and source == "MODEL" and not tcs:
                out = str(content)
                is_err = self._gemini_result_is_error(out, status)
                if pending:
                    _, tname, targs, tr = pending.pop(0)
                    cat, summ, det = categorize_tool(tname, targs, out, is_err)
                    tr.category = cat
                    tr.summary = summ
                    tr.details = det
                    tr.output = out
                    tr.is_error = is_err
                else:
                    self.notes.append(
                        f"L{idx}: tool result with no pending call (orphaned result)"
                    )
                continue

            tools: List[ToolRecord] = []
            for tc in tcs:
                tname = tc.get("name") or "tool"
                args = tc.get("args") or {}
                # Antigravity stores argument values as JSON-quoted strings.
                clean_args = {}
                for k, v in args.items():
                    if isinstance(v, str) and len(v) > 1 and v.startswith('"') and v.endswith('"'):
                        clean_args[k] = v[1:-1]
                    else:
                        clean_args[k] = v
                cat, summ, det = categorize_tool(tname, clean_args)
                tr = ToolRecord(
                    tool_id=f"gem_{idx}_{len(tools)}",
                    name=tname,
                    category=cat,
                    summary=summ,
                    details=det,
                    line_num=idx,
                )
                tools.append(tr)
                pending.append((idx, tname, clean_args, tr))

            text = str(content).strip()
            if role == "user":
                text = self._gemini_user_text(text)

            tmsg = TranscriptMessage(
                index=idx,
                role=role,
                text=text,
                timestamp=ts,
                raw_obj=obj,
            )
            tmsg.tools = tools
            msg_by_line[idx] = tmsg

        for idx, ts, err in api_errors:
            tmsg = TranscriptMessage(
                index=idx, role="system", text=err, timestamp=ts, raw_obj={}
            )
            tmsg.tools.append(
                ToolRecord(
                    tool_id=f"gem_err_{idx}",
                    name="api_error",
                    category="other",
                    summary=err[:80],
                    details={},
                    is_error=True,
                    output=err,
                    line_num=idx,
                )
            )
            msg_by_line[idx] = tmsg

        if pending:
            self.notes.append(
                f"{len(pending)} tool call(s) never received a result"
            )

        self.messages = [msg_by_line[k] for k in sorted(msg_by_line)]

    def _parse_minimax(self):
        """MiniMax Code: {"message_id", "turn_id", "message": {...}}.

        The assistant turn carries text/thinking/toolCall blocks; the tool
        result arrives as its OWN record keyed by toolCallId, so results are
        filled in by id and the order of the two streams does not matter.
        """
        tool_by_id: Dict[str, ToolRecord] = {}

        self._load_minimax_manifest()

        for idx, obj in self.raw_records:
            msg = obj.get("message") or {}
            role = msg.get("role")
            ts = msg.get("timestamp")
            content = msg.get("content")

            blocks: List[Dict[str, Any]] = []
            if isinstance(content, list):
                blocks = [b for b in content if isinstance(b, dict)]
            elif isinstance(content, str):
                blocks = [{"type": "text", "text": content}]

            if role == "custom":
                # Background-task settlement notice: no user-visible content.
                continue

            if role == "toolResult":
                tid = msg.get("toolCallId") or ""
                out, artifact = self._minimax_result_text(blocks)
                details = msg.get("details") or {}
                is_err = bool(msg.get("isError")) or details.get("status") == "failed"
                execution = details.get("execution") or {}
                if execution.get("status") == "failed":
                    is_err = True
                exit_code = execution.get("exitCode")
                if exit_code not in (0, None):
                    is_err = True
                tr = tool_by_id.get(tid)
                if tr is not None:
                    tr.output = out
                    tr.is_error = is_err
                    if artifact:
                        tr.details["externalized_artifact"] = artifact
                    if exit_code is not None:
                        tr.details["exit_code"] = exit_code
                else:
                    self.notes.append(
                        f"L{idx}: tool result with no matching call ({msg.get('toolName')})"
                    )
                continue

            if role == "user":
                text = "\n".join(
                    b.get("text", "") for b in blocks if b.get("type") == "text"
                ).strip()
                if not text:
                    continue
                self.messages.append(
                    TranscriptMessage(
                        index=idx,
                        role="user",
                        text=text,
                        timestamp=ts,
                        uuid=obj.get("message_id"),
                        raw_obj=obj,
                    )
                )
                continue

            if role == "assistant":
                text_parts: List[str] = []
                tools: List[ToolRecord] = []
                for b in blocks:
                    btype = b.get("type")
                    if btype == "text":
                        text_parts.append(b.get("text", ""))
                    elif btype == "thinking":
                        continue  # raw CoT, keep it out of the transcript view
                    elif btype == "toolCall":
                        tname = b.get("name") or "tool"
                        targs = b.get("arguments") or {}
                        cat, summ, det = categorize_tool(tname, targs)
                        tr = ToolRecord(
                            tool_id=b.get("id") or "",
                            name=tname,
                            category=cat,
                            summary=summ,
                            details=det,
                            line_num=idx,
                        )
                        tools.append(tr)
                        if tr.tool_id:
                            tool_by_id[tr.tool_id] = tr
                tmsg = TranscriptMessage(
                    index=idx,
                    role="assistant",
                    text="\n".join(text_parts).strip(),
                    timestamp=ts,
                    uuid=obj.get("message_id"),
                    raw_obj=obj,
                )
                tmsg.tools = tools
                self.messages.append(tmsg)
                continue

    @staticmethod
    def _minimax_result_text(blocks: List[Dict[str, Any]]) -> Tuple[str, Optional[str]]:
        """Return the result text and, when MiniMax externalised a large
        output to an artifact, the path of that artifact."""
        text = "\n".join(b.get("text", "") for b in blocks if b.get("type") == "text")
        artifact = None
        m = re.search(r"^Artifact:\s*(\S+)", text, re.M)
        if m:
            artifact = m.group(1)
        return text, artifact

    def _load_minimax_manifest(self):
        """MiniMax keeps the session id in a sibling manifest.json."""
        manifest = Path(self.file_path).parent / "manifest.json"
        if not manifest.exists():
            return
        try:
            with open(manifest, "r", encoding="utf-8", errors="replace") as f:
                data = json.load(f)
        except (OSError, ValueError):
            return
        sid = data.get("sessionId")
        if isinstance(sid, str):
            self.session_id = sid

    # ------------------------------------------------------------------
    # CodeBuddy CLI
    # ------------------------------------------------------------------

    @staticmethod
    def _looks_like_codebuddy(objs: List[Dict[str, Any]]) -> bool:
        for o in objs:
            meta = o.get("meta")
            if (
                o.get("type") == "session-meta"
                and isinstance(meta, dict)
                and any(str(k).startswith("codebuddy.") for k in meta)
            ):
                return True
            trace = o.get("_meta")
            if isinstance(trace, dict) and "codebuddy.session_id" in str(trace.get("baggage") or ""):
                return True
        return False

    @staticmethod
    def _codebuddy_text(content: Any) -> str:
        """Join the text of the input_text / output_text blocks."""
        if isinstance(content, str):
            return content.strip()
        if isinstance(content, dict):
            content = [content]
        parts: List[str] = []
        if isinstance(content, list):
            for b in content:
                if isinstance(b, dict) and isinstance(b.get("text"), str):
                    parts.append(b["text"])
                elif isinstance(b, str):
                    parts.append(b)
        return "\n".join(p for p in parts if p.strip()).strip()

    @staticmethod
    def _xml_tag(text: str, name: str) -> Optional[str]:
        m = re.search(r"<%s>(.*?)</%s>" % (name, name), text, re.S)
        return m.group(1).strip() if m else None

    @classmethod
    def _codebuddy_harness_event(cls, text: str) -> Optional[str]:
        """Classify a "user" record that the harness wrote, not the user.

        Returns None for a real prompt, "" for boilerplate to drop, else a
        one-line rendering of the event for the timeline.
        """
        s = text.lstrip()
        if "command-caveat" in s[:200] and s.startswith(("<system-reminder", "<local-command-caveat")):
            return ""
        if s.startswith(("<command-name>", "<command-message>")):
            name = cls._xml_tag(s, "command-name") or cls._xml_tag(s, "command-message") or "?"
            args = cls._xml_tag(s, "command-args")
            return f"command: {name}" + (f" {args}" if args else "")
        if s.startswith(("<local-command-stdout>", "<local-command-stderr>")):
            out = cls._xml_tag(s, "local-command-stdout") or cls._xml_tag(s, "local-command-stderr") or ""
            return f"command output: {out}"
        if s.startswith("<task-notification>"):
            tid = cls._xml_tag(s, "task-id") or "?"
            status = cls._xml_tag(s, "status") or "?"
            summary = html.unescape(cls._xml_tag(s, "summary") or "")
            return f"task-notification: background task {tid} {status}" + (
                f" -- {summary}" if summary else ""
            )
        return None

    def _parse_codebuddy(self):
        """CodeBuddy CLI: one record per item, chained by id / parentId.

        A model response is split into several records -- reasoning, one
        function_call per tool, an assistant message -- that share
        providerData.messageId; they are grouped back into one assistant
        turn. A function_call_result is its own record, matched by callId.
        Timestamps are epoch milliseconds.
        """
        turns: Dict[str, TranscriptMessage] = {}
        turn_model: Dict[str, str] = {}
        tool_by_id: Dict[str, ToolRecord] = {}
        answered: Set[str] = set()
        child_count: Dict[str, int] = defaultdict(int)
        interrupted = 0

        def turn_for(idx: int, obj: Dict[str, Any], mid: Optional[str]) -> TranscriptMessage:
            if mid and mid in turns:
                return turns[mid]
            tmsg = TranscriptMessage(
                index=idx,
                role="assistant",
                uuid=obj.get("id"),
                parent_uuid=obj.get("parentId"),
                timestamp=obj.get("timestamp"),
                raw_obj=obj,
            )
            self.messages.append(tmsg)
            if mid:
                turns[mid] = tmsg
            return tmsg

        for idx, obj in self.raw_records:
            t = obj.get("type")
            pd = obj.get("providerData") if isinstance(obj.get("providerData"), dict) else {}
            mid = pd.get("messageId")
            ts = obj.get("timestamp")
            if not self.session_id and isinstance(obj.get("sessionId"), str):
                self.session_id = obj["sessionId"]
            if obj.get("parentId"):
                child_count[obj["parentId"]] += 1
            if mid and pd.get("model") and mid not in turn_model:
                turn_model[mid] = str(pd["model"])

            if t == "ai-title":
                self.ai_title = obj.get("aiTitle") or self.ai_title
                continue

            if t == "function_call":
                tname = obj.get("name") or "tool"
                raw_args = obj.get("arguments")
                targs: Dict[str, Any] = {}
                if isinstance(raw_args, dict):
                    targs = raw_args
                elif isinstance(raw_args, str) and raw_args.strip():
                    try:
                        parsed = json.loads(raw_args)
                        if isinstance(parsed, dict):
                            targs = parsed
                    except json.JSONDecodeError:
                        self.notes.append(f"L{idx}: {tname} arguments are not valid JSON")
                cat, summ, det = categorize_tool(tname, targs)
                tr = ToolRecord(
                    tool_id=obj.get("callId") or "",
                    name=tname,
                    category=cat,
                    summary=summ,
                    details=det,
                    line_num=idx,
                )
                turn_for(idx, obj, mid).tools.append(tr)
                if tr.tool_id:
                    tool_by_id[tr.tool_id] = tr
                continue

            if t == "function_call_result":
                cid = obj.get("callId") or ""
                tr = tool_by_id.get(cid)
                if tr is None:
                    self.notes.append(f"L{idx}: tool result with no matching call ({obj.get('name')})")
                    continue
                answered.add(cid)
                out = self._codebuddy_text(obj.get("output"))
                raw = (pd.get("toolResult") or {}).get("rawResponse")
                raw = raw if isinstance(raw, dict) else {}
                exit_code = raw.get("exitCode") if isinstance(raw.get("exitCode"), int) else None
                if exit_code is None:
                    codes = re.findall(r"^Exit Code:\s*(-?\d+)\s*$", out, re.M)
                    if codes:
                        exit_code = int(codes[-1])
                status = obj.get("status")
                tr.output = out
                tr.is_error = (
                    (status is not None and status != "completed")
                    or exit_code not in (None, 0)
                    or raw.get("is_error") is True
                )
                if exit_code is not None:
                    tr.details["exit_code"] = exit_code
                if status not in (None, "completed"):
                    tr.details["status"] = status
                bg = re.match(r"Status: Running in background with task_id:\s*(\S+)", out)
                if bg:
                    tr.details["background_task"] = bg.group(1)
                continue

            if t != "message":
                # session-meta, reasoning, file-history-snapshot, turn-metrics,
                # summary: bookkeeping, nothing to show.
                continue

            role = obj.get("role")
            text = self._codebuddy_text(obj.get("content"))

            if role == "user":
                event = self._codebuddy_harness_event(text)
                if event is None and (pd.get("isMeta") or pd.get("skipRun")):
                    event = text  # written by the harness, never sent as a prompt
                if event == "" or (event is None and not text):
                    continue
                if event is not None and event.startswith("task-notification:"):
                    self._codebuddy_settle_background(text, tool_by_id)
                self.messages.append(
                    TranscriptMessage(
                        index=idx,
                        role="user" if event is None else "system",
                        text=text if event is None else event,
                        uuid=obj.get("id"),
                        parent_uuid=obj.get("parentId"),
                        timestamp=ts,
                        raw_obj=obj,
                    )
                )
                continue

            if role == "assistant":
                err = pd.get("error") if isinstance(pd.get("error"), dict) else None
                if pd.get("skipRun") or err:
                    # Not model output: the harness recording an interrupt
                    # or an API failure in the assistant's place.
                    err_msg = str((err or {}).get("message") or "")
                    tmsg = TranscriptMessage(
                        index=idx,
                        role="system",
                        text=text or err_msg or "(incomplete assistant message)",
                        uuid=obj.get("id"),
                        parent_uuid=obj.get("parentId"),
                        timestamp=ts,
                        raw_obj=obj,
                    )
                    if (err_msg or text) == "Interrupted by user":
                        interrupted += 1
                    elif err_msg:
                        tmsg.tools.append(
                            ToolRecord(
                                tool_id=obj.get("id") or f"cb_err_{idx}",
                                name="api_error",
                                category="other",
                                summary=err_msg[:80],
                                details={k: v for k, v in err.items() if k != "message"},
                                is_error=True,
                                output=err_msg,
                                line_num=idx,
                            )
                        )
                    self.messages.append(tmsg)
                    continue
                if text:
                    turn = turn_for(idx, obj, mid)
                    turn.text = (turn.text + "\n" + text).strip() if turn.text else text

        missing = [tr for cid, tr in tool_by_id.items() if cid not in answered]
        for tr in missing:
            tr.is_error = True
            tr.details["no_result"] = True
            tr.output = "(no function_call_result recorded: interrupted, or the session ended first)"
        if missing:
            self.notes.append(
                f"{len(missing)} tool call(s) never received a result (listed under --errors)"
            )
        if interrupted:
            self.notes.append(f"{interrupted} turn(s) interrupted by the user")
        forks = sum(1 for n in child_count.values() if n > 1)
        if forks:
            self.notes.append(
                f"id/parentId chain has {forks} fork point(s); records are shown in file order"
            )
        for model in turn_model.values():
            self.models[model] = self.models.get(model, 0) + 1

    def _codebuddy_settle_background(self, text: str, tool_by_id: Dict[str, ToolRecord]):
        """A background Bash call returns "Running in background" at once;
        its exit code arrives later in a <task-notification>. Hand it back
        to the call so a failed background command shows under --errors."""
        cid = self._xml_tag(text, "tool-use-id")
        tr = tool_by_id.get(cid or "")
        if tr is None:
            return
        status = self._xml_tag(text, "status") or ""
        summary = html.unescape(self._xml_tag(text, "summary") or "")
        m = re.search(r"exit code\s+(-?\d+)\s*$", summary)
        if m:
            code = int(m.group(1))
            tr.details["background_exit_code"] = code
            if code != 0:
                tr.is_error = True
        if status in ("failed", "error"):
            tr.is_error = True
            tr.details["background_status"] = status

    def _build_branch_indices(self):
        if self.format != "claude":
            return

        for m in self.messages:
            if m.parent_uuid:
                self.children[m.parent_uuid].append(m)

        # Find branch points (parent with > 1 children)
        for parent_uuid, child_list in self.children.items():
            if len(child_list) > 1:
                parent_msg = self.uuid_to_msg.get(parent_uuid)
                if parent_msg:
                    self.branch_points.append((parent_msg, child_list))

        self.branch_points.sort(key=lambda x: x[0].index)

        # Find branch tips (leaf nodes)
        parent_uuids = set(self.children.keys())
        tips = []
        for m in self.messages:
            if not m.uuid:
                continue
            if m.uuid not in parent_uuids or len(self.children[m.uuid]) == 0:
                # Calculate depth
                chain = self._trace_chain(m)
                tips.append((m, len(chain)))

        tips.sort(key=lambda x: -x[1])
        self.branch_tips = tips

    def _trace_chain(self, leaf_msg: TranscriptMessage) -> List[TranscriptMessage]:
        chain = []
        curr = leaf_msg
        visited = set()
        while curr:
            if curr.uuid and curr.uuid in visited:
                break
            if curr.uuid:
                visited.add(curr.uuid)
            chain.append(curr)
            if curr.parent_uuid and curr.parent_uuid in self.uuid_to_msg:
                curr = self.uuid_to_msg[curr.parent_uuid]
            else:
                break
        chain.reverse()
        return chain

    def get_branch_messages(self, branch_rank: int = 1) -> List[TranscriptMessage]:
        """Return messages along the Nth deepest branch (1 = deepest)."""
        if self.format != "claude" or not self.branch_tips:
            return self.messages

        idx = branch_rank - 1
        if idx < 0 or idx >= len(self.branch_tips):
            return self.messages

        leaf = self.branch_tips[idx][0]
        return self._trace_chain(leaf)


# ----------------------------------------------------------------------
# Inspection & Presentation Views
# ----------------------------------------------------------------------

def print_banner(title: str):
    print("=" * 78)
    print(f"  {title}")
    print("=" * 78)


def view_summary(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    all_tools = [t for m in messages for t in m.tools]
    tool_counts = defaultdict(int)
    for t in all_tools:
        tool_counts[t.name] += 1

    user_msgs = [m for m in messages if m.role == "user"]
    asst_msgs = [m for m in messages if m.role == "assistant"]
    errors = [t for t in all_tools if t.is_error]

    # Git operations count
    git_tools = [t for t in all_tools if t.category == "git"]
    # Files modified count
    file_writes = [t for t in all_tools if t.category == "file_write"]
    files_touched = set(t.details.get("file_path", "") for t in file_writes if t.details.get("file_path"))

    first_ts = next((format_timestamp(m.timestamp) for m in messages if m.timestamp), None)
    last_ts = next((format_timestamp(m.timestamp) for m in reversed(messages) if m.timestamp), None)

    print_banner("SESSION OVERVIEW")
    print(f"  File:            {parser.file_path}")
    print(f"  Format:          {parser.format.upper()} ({len(parser.raw_records)} raw records)")
    if parser.ai_title:
        print(f"  AI Title:        {parser.ai_title}")
    if parser.session_id:
        print(f"  Session ID:      {parser.session_id}")
    if parser.models:
        print("  Model:           " + ", ".join(
            f"{name} ({n} response{'s' if n != 1 else ''})" if len(parser.models) > 1 else name
            for name, n in sorted(parser.models.items(), key=lambda x: -x[1])
        ))
    if first_ts and last_ts:
        print(f"  Time Range:      {first_ts} -> {last_ts}")

    print()
    print_banner("CONVERSATION STRUCTURE")
    print(f"  User Prompts:    {len(user_msgs)}")
    print(f"  Assistant Turns: {len(asst_msgs)}")
    print(f"  Total Tool Calls:{len(all_tools)}")
    print(f"  Tool Errors:     {len(errors)}")

    if parser.format == "claude":
        branch_count = len(parser.branch_tips)
        fork_count = len(parser.branch_points)
        status = "Linear (No branches)" if fork_count == 0 else f"Branched ({fork_count} fork points, {branch_count} leaf tips)"
        print(f"  DAG Topology:    {status}")
        if branch_filter:
            print(f"  Scoped Branch:   #{branch_filter} (of {branch_count})")
    else:
        print("  Topology:        Linear (single-stream transcript, no DAG)")

    print()
    print_banner("KEY ACTIVITIES")
    print(f"  Git Operations:  {len(git_tools)}")
    print(f"  Files Modified:  {len(files_touched)}")
    if files_touched:
        print("  Touched Paths:   " + ", ".join(Path(p).name for p in sorted(files_touched)[:8]) + ("..." if len(files_touched) > 8 else ""))

    print()
    print_banner("TOOL CALL BREAKDOWN")
    for name, count in sorted(tool_counts.items(), key=lambda x: -x[1]):
        bar = "■" * min(30, max(1, int(count * 30 / (len(all_tools) or 1))))
        print(f"  {name:<20} {count:>4}  {bar}")

    if parser.notes:
        print()
        print_banner(f"TRANSCRIPT NOTES ({len(parser.notes)})")
        for note in parser.notes:
            print(f"  - {note}")


def view_changes(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    all_tools = [t for m in messages for t in m.tools]
    file_writes = [t for t in all_tools if t.category == "file_write"]
    git_tools = [t for t in all_tools if t.category == "git"]

    print_banner(f"FILE MODIFICATIONS AUDIT ({len(file_writes)} edit/write operations)")

    # Group by file path
    by_file: Dict[str, List[ToolRecord]] = defaultdict(list)
    for t in file_writes:
        path = t.details.get("file_path", "unknown")
        by_file[path].append(t)

    if not by_file:
        print("  No file modifications recorded in this session.")
    else:
        for path, ops in sorted(by_file.items(), key=lambda x: len(x[1]), reverse=True):
            print(f"\n  📄 {path}  ({len(ops)} operations)")
            for op in ops:
                status_icon = "❌" if op.is_error else "✓"
                print(f"     L{op.line_num:<4} {status_icon} {op.name:<6} {op.summary}")

    print()
    print_banner(f"GIT OPERATIONS AUDIT ({len(git_tools)} git commands executed)")
    if not git_tools:
        print("  No git operations recorded in this session.")
    else:
        for t in git_tools:
            status_icon = "❌" if t.is_error else "✓"
            tool = t.details.get("git_tool", "git")
            sub = t.details.get("git_subcommand", "")
            args = t.details.get("git_args", "")
            print(f"  L{t.line_num:<4} {status_icon} {tool} {sub:<10} {args}")


def view_git(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    git_tools = [t for m in messages for t in m.tools if t.category == "git"]

    print_banner(f"DETAILED GIT AUDIT ({len(git_tools)} operations)")
    if not git_tools:
        print("  No git operations found.")
        return

    for idx, t in enumerate(git_tools, 1):
        tool = t.details.get("git_tool", "git")
        sub = t.details.get("git_subcommand", "")
        cmd = t.details.get("command", "")
        desc = t.details.get("description", "")
        out = t.output.strip()
        status = "FAILED" if t.is_error else "SUCCESS"

        print(f"\n[{idx}] {tool} {sub} (Status: {status} | Line {t.line_num})")
        if desc:
            print(f"    Intent:  {desc}")
        print(f"    Command: {cmd}")
        if out:
            out_preview = "\n".join("    | " + l for l in out.splitlines()[:6])
            print(f"    Output:\n{out_preview}")
            if len(out.splitlines()) > 6:
                print(f"    | ... ({len(out.splitlines()) - 6} more lines)")


def view_timeline(
    parser: TranscriptParser,
    branch_filter: Optional[int] = None,
    tools_only: bool = False,
    user_only: bool = False,
    full_text: bool = False,
    max_items: Optional[int] = None,
):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    if user_only:
        messages = [m for m in messages if m.role == "user"]
    elif tools_only:
        messages = [m for m in messages if m.tools]

    if max_items:
        messages = messages[:max_items]

    print_banner(f"CONVERSATION TIMELINE ({len(messages)} events)")

    for m in messages:
        ts_value = format_timestamp(m.timestamp)
        ts = f" [{ts_value}]" if ts_value else ""
        role_label = "🧑 USER" if m.role == "user" else "🤖 ASSISTANT" if m.role == "assistant" else "⚙️ SYSTEM"

        print(f"\n--- L{m.index} {role_label}{ts} ---")

        if m.text and not tools_only:
            if full_text:
                print(m.text)
            else:
                lines = m.text.strip().splitlines()
                preview = preview_line(m.text)
                print(f"  {preview}" + ("..." if len(m.text) > 100 or len(lines) > 1 else ""))

        for t in m.tools:
            icon = "❌" if t.is_error else "🔧"
            print(f"    {icon} [{t.name}] {t.summary}")
            if full_text and t.output:
                out_snippet = "\n".join("      | " + l for l in t.output.splitlines()[:4])
                print(out_snippet)


def view_errors(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    all_tools = [t for m in messages for t in m.tools]
    errors = [t for t in all_tools if t.is_error]

    print_banner(f"FAILED TOOL EXECUTIONS & ERRORS ({len(errors)} found)")
    if not errors:
        print("  ✓ No failed tool operations detected in this session!")
        return

    for idx, e in enumerate(errors, 1):
        print(f"\n[{idx}] Line {e.line_num}: Tool [{e.name}] Failed")
        print(f"    Summary: {e.summary}")
        if "command" in e.details:
            print(f"    Command: {e.details['command']}")
        # The exit code often sits at the END of the output, past the
        # 8-line preview below, so state it up front.
        for key, label in (("exit_code", "Exit Code"), ("background_exit_code", "Background Exit Code")):
            if e.details.get(key) not in (None, 0):
                print(f"    {label}: {e.details[key]}")
        if e.details.get("externalized_artifact"):
            print(f"    Artifact: {e.details['externalized_artifact']}")
        if e.output:
            lines = e.output.strip().splitlines()
            print("    Error Output:")
            for l in lines[:8]:
                print(f"      {l}")
            if len(lines) > 8:
                print(f"      ... ({len(lines) - 8} more lines)")


def search_transcript(
    parser: TranscriptParser,
    query: str,
    branch_filter: Optional[int] = None,
    full_text: bool = False,
):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    q_lower = query.lower()
    matches = []

    for m in messages:
        # Match message text
        if q_lower in m.text.lower():
            matches.append((m.index, m.role, "message", m.text))

        # Match tools
        for t in m.tools:
            t_str = f"{t.name} {t.summary} {json.dumps(t.details)} {t.output}"
            if q_lower in t_str.lower():
                matches.append((t.line_num, m.role, f"tool:{t.name}", t.summary + " | " + t.output[:200]))

    print_banner(f"SEARCH RESULTS FOR '{query}' ({len(matches)} matches)")
    if not matches:
        print("  No matches found.")
        return

    for line_num, role, match_type, content in matches:
        print(f"\n  [L{line_num}] ({role} | {match_type})")
        lines = content.strip().splitlines()
        if full_text:
            for l in lines:
                print(f"    {l}")
        else:
            for l in lines[:3]:
                print(f"    {l[:100]}")
            if len(lines) > 3:
                print(f"    ... ({len(lines) - 3} more lines)")


def diff_branches(parser: TranscriptParser, rank_a: int, rank_b: int):
    if parser.format != "claude":
        print("Branch comparison is only supported for Claude Code DAG transcripts.")
        return

    if not parser.branch_tips:
        print("No branches found in this transcript — conversation is linear.")
        return

    if rank_a < 1 or rank_a > len(parser.branch_tips):
        print(f"Invalid branch #{rank_a}. Available: 1..{len(parser.branch_tips)}")
        return
    if rank_b < 1 or rank_b > len(parser.branch_tips):
        print(f"Invalid branch #{rank_b}. Available: 1..{len(parser.branch_tips)}")
        return

    chain_a = parser.get_branch_messages(rank_a)
    chain_b = parser.get_branch_messages(rank_b)

    uuids_a = set(m.uuid for m in chain_a if m.uuid)
    uuids_b = set(m.uuid for m in chain_b if m.uuid)

    common_uuids = uuids_a.intersection(uuids_b)
    unique_a = [m for m in chain_a if m.uuid not in common_uuids]
    unique_b = [m for m in chain_b if m.uuid not in common_uuids]

    # Find the fork point (last common message)
    last_common = None
    for m in chain_a:
        if m.uuid in common_uuids:
            last_common = m

    print_banner(f"BRANCH COMPARISON: #{rank_a} (Depth {len(chain_a)}) vs #{rank_b} (Depth {len(chain_b)})")

    if last_common:
        print(f"\n🌱 Fork Point:")
        print(f"   Line {last_common.index}: [{last_common.role}] {last_common.text[:100]}")

    print(f"\n🌿 Branch #{rank_a} Divergence ({len(unique_a)} unique turns):")
    tools_a = [t for m in unique_a for t in m.tools]
    files_a = set(t.details.get("file_path", "") for t in tools_a if t.category == "file_write")
    git_a = [t for t in tools_a if t.category == "git"]
    print(f"   Tools called: {len(tools_a)} (Git: {len(git_a)}, Files modified: {len(files_a)})")
    if files_a:
        print(f"   Modified files: {', '.join(Path(p).name for p in files_a if p)}")
    for m in unique_a[:5]:
        print(f"   - L{m.index} [{m.role}] {m.text[:80]}")
        for t in m.tools:
            print(f"       🔧 {t.summary}")
    if len(unique_a) > 5:
        print(f"   ... ({len(unique_a) - 5} more unique messages)")

    print(f"\n🍂 Branch #{rank_b} Divergence ({len(unique_b)} unique turns):")
    tools_b = [t for m in unique_b for t in m.tools]
    files_b = set(t.details.get("file_path", "") for t in tools_b if t.category == "file_write")
    git_b = [t for t in tools_b if t.category == "git"]
    print(f"   Tools called: {len(tools_b)} (Git: {len(git_b)}, Files modified: {len(files_b)})")
    if files_b:
        print(f"   Modified files: {', '.join(Path(p).name for p in files_b if p)}")
    for m in unique_b[:5]:
        print(f"   - L{m.index} [{m.role}] {m.text[:80]}")
        for t in m.tools:
            print(f"       🔧 {t.summary}")
    if len(unique_b) > 5:
        print(f"   ... ({len(unique_b) - 5} more unique messages)")


def export_markdown(parser: TranscriptParser, out_file: str, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    all_tools = [t for m in messages for t in m.tools]
    file_writes = [t for t in all_tools if t.category == "file_write"]
    git_tools = [t for t in all_tools if t.category == "git"]

    lines = []
    lines.append(f"# Conversation Audit Report")
    lines.append(f"")
    lines.append(f"- **Source Transcript**: `{parser.file_path}`")
    lines.append(f"- **Format**: {parser.format.upper()}")
    if parser.ai_title:
        lines.append(f"- **AI Title**: {parser.ai_title}")
    if parser.session_id:
        lines.append(f"- **Session ID**: `{parser.session_id}`")
    if branch_filter:
        lines.append(f"- **Scoped Branch**: #{branch_filter}")
    lines.append(f"- **Generated At**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"")

    lines.append(f"## 1. Executive Summary")
    lines.append(f"")
    lines.append(f"| Metric | Count |")
    lines.append(f"| :--- | :--- |")
    lines.append(f"| User Prompts | {len([m for m in messages if m.role == 'user'])} |")
    lines.append(f"| Assistant Turns | {len([m for m in messages if m.role == 'assistant'])} |")
    lines.append(f"| Total Tool Executions | {len(all_tools)} |")
    lines.append(f"| Git Operations | {len(git_tools)} |")
    lines.append(f"| Files Modified | {len(set(t.details.get('file_path', '') for t in file_writes if t.details.get('file_path')))} |")
    lines.append(f"| Tool Failures/Errors | {len([t for t in all_tools if t.is_error])} |")
    lines.append(f"")

    if file_writes:
        lines.append(f"## 2. Modified Files")
        lines.append(f"")
        lines.append(f"| Line | Operation | File | Detail | Status |")
        lines.append(f"| :--- | :--- | :--- | :--- | :--- |")
        for t in file_writes:
            path = t.details.get("file_path", "")
            stat = "❌ Failed" if t.is_error else "✓ OK"
            lines.append(f"| L{t.line_num} | `{t.name}` | `{path}` | {t.summary} | {stat} |")
        lines.append(f"")

    if git_tools:
        lines.append(f"## 3. Git Operations")
        lines.append(f"")
        lines.append(f"| Line | Command | Intent | Status |")
        lines.append(f"| :--- | :--- | :--- | :--- |")
        for t in git_tools:
            cmd = t.details.get("command", "")
            desc = t.details.get("description", "") or "-"
            stat = "❌ Failed" if t.is_error else "✓ OK"
            lines.append(f"| L{t.line_num} | `{cmd[:60]}` | {desc[:40]} | {stat} |")
        lines.append(f"")

    lines.append(f"## 4. Conversation Transcript")
    lines.append(f"")
    for m in messages:
        role_hdr = "🧑 User" if m.role == "user" else "🤖 Assistant" if m.role == "assistant" else "⚙️ System"
        ts_value = format_timestamp(m.timestamp)  # ISO strings pass through unchanged
        ts_str = f" ({ts_value})" if ts_value else ""
        lines.append(f"### [L{m.index}] {role_hdr}{ts_str}")
        lines.append(f"")
        if m.text:
            lines.append(m.text)
            lines.append(f"")
        for t in m.tools:
            icon = "❌" if t.is_error else "🔧"
            lines.append(f"> {icon} **`{t.name}`**: {t.summary}")
            if t.output:
                preview = t.output.strip()[:200]
                lines.append(f"> ```text")
                lines.append(f"> {preview}")
                lines.append(f"> ```")
        lines.append(f"")

    out_p = Path(out_file)
    out_p.parent.mkdir(parents=True, exist_ok=True)
    with open(out_p, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"Exported Markdown audit report to: {out_file}")


def export_json(parser: TranscriptParser, branch_filter: Optional[int] = None):
    messages = (
        parser.get_branch_messages(branch_filter)
        if branch_filter is not None
        else parser.messages
    )

    data = {
        "file": parser.file_path,
        "format": parser.format,
        "ai_title": parser.ai_title,
        "session_id": parser.session_id,
        "branch_filter": branch_filter,
        "total_messages": len(messages),
        "messages": [m.to_dict() for m in messages],
    }
    if parser.models:
        data["models"] = parser.models
    # On a non-UTF stream (a GBK console) \uXXXX escapes keep the JSON
    # lossless where the output error handler would have to write '?'.
    print(json.dumps(data, indent=2, ensure_ascii=not stdout_is_unicode()))


# ----------------------------------------------------------------------
# Main CLI Entry Point
# ----------------------------------------------------------------------

def main():
    make_output_safe()
    parser = argparse.ArgumentParser(
        description="Inspect, audit, and analyze coding agent conversation transcripts."
    )
    parser.add_argument("transcript", help="Path to conversation transcript JSONL file")
    parser.add_argument("--summary", action="store_true", help="Display overview summary (default)")
    parser.add_argument("--changes", action="store_true", help="Audit all file modifications and git commands")
    parser.add_argument("--git", action="store_true", help="Detailed audit of all Git operations")
    parser.add_argument("--timeline", action="store_true", help="Chronological conversation timeline")
    parser.add_argument("--errors", action="store_true", help="Show all failed tool calls and errors")
    parser.add_argument("--search", "--grep", dest="query", help="Search for keyword in messages and tools")
    parser.add_argument("--diff-branches", nargs=2, type=int, metavar=("A", "B"), help="Compare divergence between branch A and B")
    parser.add_argument("--branch", type=int, metavar="N", help="Scope analysis to Nth deepest branch (1=deepest)")
    parser.add_argument("--export-md", metavar="FILE", help="Export audit report and transcript to Markdown file")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    parser.add_argument("--full", action="store_true", help="Display full text content without truncation")
    parser.add_argument("--tools-only", action="store_true", help="Timeline view shows only tool invocations")
    parser.add_argument("--user-only", action="store_true", help="Timeline view shows only user prompts")
    parser.add_argument("--limit", type=int, metavar="N", help="Limit number of items displayed")

    args = parser.parse_args()

    try:
        t_parser = TranscriptParser(args.transcript)
    except Exception as e:
        print(f"Error reading transcript: {e}", file=sys.stderr)
        sys.exit(1)

    # Route execution
    if args.json:
        export_json(t_parser, args.branch)
    elif args.export_md:
        export_markdown(t_parser, args.export_md, args.branch)
    elif args.diff_branches:
        diff_branches(t_parser, args.diff_branches[0], args.diff_branches[1])
    elif args.query:
        search_transcript(t_parser, args.query, args.branch, args.full)
    elif args.errors:
        view_errors(t_parser, args.branch)
    elif args.git:
        view_git(t_parser, args.branch)
    elif args.changes:
        view_changes(t_parser, args.branch)
    elif args.timeline:
        view_timeline(
            t_parser,
            branch_filter=args.branch,
            tools_only=args.tools_only,
            user_only=args.user_only,
            full_text=args.full,
            max_items=args.limit,
        )
    else:
        view_summary(t_parser, args.branch)


if __name__ == "__main__":
    main()
