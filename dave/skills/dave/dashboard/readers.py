"""Direct readers over the DAVE_HOME state tree.

Reads are cheap and must never mutate, so the dashboard parses the markdown
and JSON files itself instead of shelling out. Anything that writes still goes
through DaveCli — dave.sh is the only writer.

Structured state (state.json, notes.json, commitments.json, missions.json,
sessions.jsonl, assignments.jsonl) lives under ``.local/views/`` — derived
files rebuilt from the event journal in ``journal/``. Prose and config stay
at the tree root.
"""

from __future__ import annotations

import fcntl
import json
import threading
from contextlib import contextmanager
from collections.abc import Iterator
import re
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

_REDACT_KEY = re.compile(r"key|token|secret|password", re.IGNORECASE)
_ITEM_RE = re.compile(r"^\s*(?:(\d+)\.|[-*])\s+(.*\S)\s*$")
_REF_RE = re.compile(r"\*\*([^*]+)\*\*")
_RECONCILED_RE = re.compile(r"_Last reconciled:\s*([^_]+)_")
_PARKED_RE = re.compile(r"_\(parked ([0-9]{4}-[0-9]{2}-[0-9]{2})[^)]*?\)_")
_WHILE_ON_RE = re.compile(r", while on ([^)_]+)\)_")
_RETIRED_RE = re.compile(r"_\(retired ([0-9]{4}-[0-9]{2}-[0-9]{2})\)_")
_LOG_ENTRY_RE = re.compile(r"^- `(\d{2}:\d{2})` (?:\*\*([^*]+)\*\* — )?(.*)$")

PRIORITY_SECTIONS = ("now", "next", "blocked", "someday")

# Derived views: the journal reducer writes these under .local/views/.
_VIEWS = ".local/views"


class StateReader:
    """Parses the state tree's files into dashboard-ready structures."""

    def __init__(self, dave_home: str | Path) -> None:
        """Bind the reader to a state directory.

        Args:
            dave_home: Absolute path to the state tree.
        """
        self.home = Path(dave_home)
        self._snapshot = threading.local()

    @contextmanager
    def snapshot(self) -> Iterator[None]:
        """Pin a generation lazily for one request, releasing its lease on exit.

        Returns:
            A context in which all derived reads use the same generation.
        """
        self._snapshot.active = True
        self._snapshot.generation = None
        self._snapshot.lease = None
        try:
            yield
        finally:
            lease = self._snapshot.lease
            if lease is not None:
                lease.close()
            self._snapshot.active = False
            self._snapshot.generation = None
            self._snapshot.lease = None

    def _derived_path(self, name: str) -> Path:
        """Resolve derived paths under a leased generation for this request.

        Args:
            name: A vault-relative filename.

        Returns:
            The pinned filename, or its legacy location before cache migration.
        """
        if not name.startswith((".local/views/", ".local/render/")):
            return self.home / name
        if not getattr(self._snapshot, "active", False):
            return self.home / name
        generation = self._snapshot.generation
        if generation is None:
            local = self.home / ".local"
            try:
                with (local / "publication.lock").open("rb") as publication:
                    fcntl.flock(publication, fcntl.LOCK_SH)
                    generation = (local / "current").resolve(strict=True)
                    if generation.parent != (local / "generations").resolve():
                        raise OSError("invalid generation location")
                    lease = (generation / ".lease").open("rb")
                    fcntl.flock(lease, fcntl.LOCK_SH)
                    self._snapshot.generation = generation
                    self._snapshot.lease = lease
            except FileNotFoundError:
                return self.home / name
        return generation / name.removeprefix(".local/")

    def _read_text(self, name: str) -> str:
        """Read a file under DAVE_HOME, or empty string when absent.

        Args:
            name: Path relative to the state directory.

        Returns:
            The file's text, or "" when missing.
        """
        try:
            return self._derived_path(name).read_text(encoding="utf-8", errors="replace")
        except OSError:
            return ""

    def _read_json(self, name: str, default: Any) -> Any:
        """Read a JSON file under DAVE_HOME.

        Args:
            name: Path relative to the state directory.
            default: Value returned for missing or malformed files.

        Returns:
            The decoded JSON value, or default.
        """
        try:
            return json.loads(self._read_text(name))
        except (json.JSONDecodeError, ValueError):
            return default

    def _read_jsonl(self, name: str) -> list[dict[str, Any]]:
        """Read a JSONL file, skipping malformed lines.

        Args:
            name: Path relative to the state directory.

        Returns:
            The well-formed object records, in file order.
        """
        out: list[dict[str, Any]] = []
        for line in self._read_text(name).splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                out.append(obj)
        return out

    # ---------------------------------------------------------------- files

    def config(self, redact: bool = True) -> dict[str, Any]:
        """The merged config: config.json with .local/config.json over it.

        Mirrors dave.sh's `_config_merged` — local keys win, so the dashboard
        shows what the commands actually use.

        Args:
            redact: Replace values under keys named key/token/secret/password.

        Returns:
            The merged config object.
        """
        shared = self._read_json("config.json", {})
        local = self._read_json(".local/config.json", {})
        cfg = _deep_merge(
            shared if isinstance(shared, dict) else {},
            local if isinstance(local, dict) else {})
        return _redact(cfg) if redact and isinstance(cfg, dict) else cfg

    def local_config_keys(self) -> list[str]:
        """Top-level keys supplied by .local/config.json.

        Returns:
            Key names, sorted; [] when there is no local config.
        """
        local = self._read_json(".local/config.json", {})
        return sorted(local.keys()) if isinstance(local, dict) else []

    def local_project_paths(self) -> dict[str, str]:
        """The device-local slug → checkout map.

        Returns:
            The projects.paths object from .local/config.json, or {}.
        """
        local = self._read_json(".local/config.json", {})
        paths = (local.get("projects") or {}).get("paths") \
            if isinstance(local, dict) else None
        return paths if isinstance(paths, dict) else {}

    def state(self) -> dict[str, Any]:
        """state.json.

        Returns:
            The state object.
        """
        return self._read_json(f"{_VIEWS}/state.json", {})

    def priorities(self) -> dict[str, Any]:
        """priorities.md parsed into its four ranked sections.

        Returns:
            {raw, reconciled, sections{now,next,blocked,someday}} where each
            item is {rank, ref, text}. HTML comments and italic explainer
            lines are skipped; ref is the first bold token, if any.
        """
        raw = self._read_text("priorities.md")
        m = _RECONCILED_RE.search(raw)
        sections: dict[str, list[dict[str, Any]]] = {s: [] for s in PRIORITY_SECTIONS}
        current: str | None = None
        bullets = 0
        for line in raw.splitlines():
            head = re.match(r"^##\s+(.*)", line)
            if head:
                name = head.group(1).strip().lower()
                current = name if name in sections else None
                bullets = 0
                continue
            if current is None:
                continue
            stripped = line.strip()
            if not stripped or stripped.startswith("<!--") or stripped.startswith("_"):
                continue
            item = _ITEM_RE.match(line)
            if not item:
                continue
            if item.group(1) is not None:
                rank = int(item.group(1))
            else:
                bullets += 1
                rank = bullets
            ref_m = _REF_RE.search(item.group(2))
            raw_text = item.group(2).strip()
            text = raw_text
            ref = ref_m.group(1) if ref_m else None
            if ref is not None:
                # The ref already renders in its own column; a leading
                # `**REF** — ` would duplicate it in the text.
                text = re.sub(
                    r"^\*\*" + re.escape(ref) + r"\*\*\s+[—–-]\s*", "",
                    raw_text)
            sections[current].append(
                {"rank": rank, "ref": ref, "text": text, "raw": raw_text}
            )
        return {"raw": raw, "reconciled": m.group(1).strip() if m else None,
                "sections": sections}

    def parking(self) -> dict[str, Any]:
        """parking-lot.md split into open and retired items.

        Returns:
            {open: [{index, text, parked, while_on}], retired: [...]} where
            index is the 1-based position among `- [ ]` lines — the same
            numbering `parked done <n>` takes.
        """
        open_items: list[dict[str, Any]] = []
        retired: list[dict[str, Any]] = []
        for line in self._read_text(".local/render/parking-lot.md").splitlines():
            for mark, bucket in (("- [ ]", open_items), ("- [x]", retired)):
                if line.startswith(mark):
                    raw_text = line[len(mark):].strip()
                    text = _PARKED_RE.sub("", raw_text)
                    text = _RETIRED_RE.sub("", text).strip()
                    entry: dict[str, Any] = {
                        "raw": raw_text,
                        "text": text,
                        "parked": _group(_PARKED_RE, raw_text),
                        "while_on": _group(_WHILE_ON_RE, raw_text),
                    }
                    if bucket is open_items:
                        entry["index"] = len(open_items) + 1
                    else:
                        entry["retired"] = _group(_RETIRED_RE, raw_text)
                    bucket.append(entry)
                    break
        return {"open": open_items, "retired": retired}

    def logs(self, days: int = 7) -> list[dict[str, Any]]:
        """Day logs for the last N days that have a file.

        Args:
            days: How many days back to look.

        Returns:
            [{date, entries: [{time, ref, text}]}], newest first.
        """
        out: list[dict[str, Any]] = []
        for i in range(days):
            day = (date.today() - timedelta(days=i)).isoformat()
            text = self._read_text(f".local/render/log/{day}.md")
            if not text:
                continue
            entries = []
            for line in text.splitlines():
                m = _LOG_ENTRY_RE.match(line)
                if m:
                    entries.append({"time": m.group(1), "ref": m.group(2),
                                    "text": m.group(3).strip()})
            out.append({"date": day, "entries": entries})
        return out

    def notes(self) -> dict[str, Any]:
        """notes.json — next-action notes by ref.

        Returns:
            The notes object.
        """
        return self._read_json(f"{_VIEWS}/notes.json", {})

    def commitments(self) -> list[dict[str, Any]]:
        """commitments.json.

        Returns:
            The commitments array, or [] when absent/malformed.
        """
        data = self._read_json(f"{_VIEWS}/commitments.json", [])
        return data if isinstance(data, list) else []

    def sessions(self) -> list[dict[str, Any]]:
        """sessions.jsonl — closed focus segments.

        Returns:
            The segment records.
        """
        return self._read_jsonl(f"{_VIEWS}/sessions.jsonl")

    def assignment_rows(self) -> list[dict[str, Any]]:
        """assignments.jsonl folded into one row per charge.

        Mirrors lib/mission.sh `_mission_rows`: assign events are the rows, and
        the reducer has already folded each grade onto the assignment it named
        by entity identity, so the verdict is read from the row itself.

        Returns:
            Rows with id, entity_id, mission, agent, model, charge, ref,
            project, assigned, verdict, summary, returned.
        """
        events = self._read_jsonl(f"{_VIEWS}/assignments.jsonl")
        return [
            {
                "id": a.get("id"),
                "entity_id": a.get("entity_id", ""),
                "mission": a.get("mission", ""),
                "agent": a.get("agent", ""),
                "model": a.get("model", ""),
                "charge": a.get("charge", ""),
                "ref": a.get("ref", ""),
                "project": a.get("project", ""),
                "assigned": a.get("ts"),
                "verdict": a.get("verdict"),
                "summary": a.get("summary", ""),
                "returned": a.get("returned"),
            }
            for a in events
            if a.get("type") == "assign"
        ]

    def missions(self) -> dict[str, Any]:
        """missions.json.

        Returns:
            The mission metadata object keyed by slug.
        """
        data = self._read_json(f"{_VIEWS}/missions.json", {})
        return data if isinstance(data, dict) else {}

    def projects(self) -> list[dict[str, Any]]:
        """Every registered project, shared document merged with derived
        state and this device's checkout path.

        project.json is the identity; refs/last_touched come from
        .local/views/projects.json and `path` from .local/config.json's
        projects.paths (None where this device has no checkout).

        Returns:
            The project objects, sorted by slug.
        """
        view = self._read_json(f"{_VIEWS}/projects.json", {})
        if not isinstance(view, dict):
            view = {}
        paths = self.local_project_paths()
        base = self.home / "projects"
        out: list[dict[str, Any]] = []
        if base.is_dir():
            for path in sorted(base.glob("*/project.json")):
                try:
                    obj = json.loads(path.read_text(encoding="utf-8",
                                                      errors="replace"))
                except (json.JSONDecodeError, OSError):
                    continue
                if isinstance(obj, dict):
                    slug = obj.get("slug", "")
                    derived = view.get(slug) or {}
                    obj.setdefault("refs", [])
                    obj.setdefault("last_touched", None)
                    obj.update({k: v for k, v in derived.items()
                                if k in ("refs", "last_touched")})
                    obj["path"] = paths.get(slug)
                    out.append(obj)
        return out

    def scan_cache(self) -> dict[str, Any]:
        """scan-cache.json.

        Returns:
            The cache object ({generated, entries}), or {} when absent.
        """
        data = self._read_json(".local/scan-cache.json", {})
        return data if isinstance(data, dict) else {}

    def intake_files(self) -> list[str]:
        """Filenames archived under intake/.

        Returns:
            Sorted basenames.
        """
        base = self.home / "intake"
        if not base.is_dir():
            return []
        return sorted(p.name for p in base.iterdir() if p.is_file())

    def intake_file(self, name: str) -> str | None:
        """One archived intake file, traversal-safe.

        Args:
            name: Basename only — anything with a path part is rejected.

        Returns:
            The file's text, or None when invalid/missing.
        """
        if not name or Path(name).name != name:
            return None
        path = self.home / "intake" / name
        try:
            if not path.is_file():
                return None
            return path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None


def _group(pattern: re.Pattern[str], text: str) -> str | None:
    """First capture group of a pattern, or None.

    Args:
        pattern: Compiled regex with at least one group.
        text: Text to search.

    Returns:
        The captured string stripped, or None.
    """
    m = pattern.search(text)
    return m.group(1).strip() if m else None


def _deep_merge(shared: dict[str, Any], local: dict[str, Any]) -> dict[str, Any]:
    """Deep-merge two dicts, local winning — mirrors `_config_merged` in
    common.sh. Explicit local values (including False/None) always win;
    absent keys fall through to shared.

    Args:
        shared: The vault's config.json.
        local: The device's .local/config.json.

    Returns:
        The merged dict (inputs are not mutated).
    """
    out = dict(shared)
    for key, value in local.items():
        if key in out and isinstance(out[key], dict) and isinstance(value, dict):
            out[key] = _deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def _redact(value: Any) -> Any:
    """Recursively mask values under credential-shaped keys.

    Args:
        value: Any decoded JSON value.

    Returns:
        The value with sensitive leaves replaced by "***".
    """
    if isinstance(value, dict):
        return {
            k: ("***" if _REDACT_KEY.search(k) else _redact(v))
            for k, v in value.items()
        }
    if isinstance(value, list):
        return [_redact(v) for v in value]
    return value


def iso_minutes(started: str | None) -> int | None:
    """Whole minutes between an ISO timestamp and now.

    Args:
        started: ISO 8601 timestamp, or None.

    Returns:
        Elapsed minutes, or None when the timestamp is missing/unreadable.
    """
    if not started:
        return None
    try:
        start = datetime.fromisoformat(started)
    except ValueError:
        return None
    delta = datetime.now(start.tzinfo) - start if start.tzinfo else datetime.now() - start
    return int(delta.total_seconds() // 60)
