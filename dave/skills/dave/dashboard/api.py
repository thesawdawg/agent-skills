"""HTTP route table and handlers for the dashboard API.

Every response uses the shared envelope: {"status": "success", "data": ...} or
{"status": "error", "errors": [{"message": ...}]}. Reads come from StateReader
or `dave.sh --json`; writes always go through DaveCli.
"""

from __future__ import annotations

import json
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Callable

from dave_cli import DaveCli, DaveError
from readers import StateReader, iso_minutes

PROJECT_STATUSES = ("active", "paused", "maintenance", "archived")
PROJECT_CADENCES = ("daily", "weekly", "monthly", "dormant")
MISSION_VERDICTS = ("trust", "partial", "rerun", "discard")
DRIFT_KINDS = ("unlisted", "third-repo", "parked-resurfaced", "no-focus")
DRIFT_OUTCOMES = ("parked", "promoted", "continued")


class ApiError(Exception):
    """A request that cannot be served, with its HTTP status.

    Attributes:
        status: HTTP status code.
        message: Human-readable explanation.
    """

    def __init__(self, status: int, message: str) -> None:
        """Store the status and message.

        Args:
            status: HTTP status code.
            message: Human-readable explanation.
        """
        super().__init__(message)
        self.status = status
        self.message = message


def _require(body: dict[str, Any], *fields: str) -> None:
    """Assert required fields are present and non-empty.

    Args:
        body: The decoded JSON body.
        *fields: Required field names.

    Raises:
        ApiError: 400 naming the first missing field.
    """
    for field in fields:
        if body.get(field) in (None, ""):
            raise ApiError(400, f"missing required field: {field}")


def _one_of(body: dict[str, Any], field: str, allowed: tuple[str, ...]) -> str:
    """Assert a field is one of an enumerated set.

    Args:
        body: The decoded JSON body.
        field: Field name.
        allowed: Allowed values.

    Returns:
        The field's value.

    Raises:
        ApiError: 400 when missing or not in the set.
    """
    value = body.get(field)
    if value not in allowed:
        raise ApiError(400, f"{field} must be one of: {', '.join(allowed)}")
    return str(value)


def _days(params: dict[str, list[str]], default: int = 7, cap: int = 90) -> int:
    """Parse a ?days= query parameter with sane bounds.

    Args:
        params: Parsed query string.
        default: Value when absent.
        cap: Maximum accepted.

    Returns:
        The day count.

    Raises:
        ApiError: 400 on a non-numeric value.
    """
    raw = params.get("days", [None])[0]
    if raw is None:
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise ApiError(400, "days must be a number") from exc
    return max(1, min(value, cap))


class DashboardApi:
    """Handlers for every /api/* route, bound to one state tree."""

    def __init__(self, dave_home: str | Path, cli: DaveCli) -> None:
        """Bind handlers to a reader and a CLI wrapper.

        Args:
            dave_home: Absolute path to the state tree.
            cli: The dave.sh wrapper used for --json reads and all writes.
        """
        self.reader = StateReader(dave_home)
        self.cli = cli
        self.dave_home = str(dave_home)
        self.get_routes: dict[str, Callable[[dict[str, list[str]]], Any]] = {
            "/api/health": self.health,
            "/api/overview": self.overview,
            "/api/priorities": self.priorities,
            "/api/time": self.time,
            "/api/missions": self.missions,
            "/api/assignments": self.assignments,
            "/api/projects": self.projects,
            "/api/review": self.review,
            "/api/drift": self.drift,
            "/api/promises": self.promises,
            "/api/parked": self.parked,
            "/api/log": self.log,
            "/api/notes": self.notes,
            "/api/intake": self.intake,
            "/api/sync": self.sync,
            "/api/config": self.config,
        }
        self.post_routes: dict[str, Callable[[dict[str, Any]], Any]] = {
            "/api/focus": self.post_focus,
            "/api/next": self.post_next,
            "/api/log": self.post_log,
            "/api/park": self.post_park,
            "/api/parked/done": self.post_parked_done,
            "/api/promise": self.post_promise,
            "/api/drift/record": self.post_drift_record,
            "/api/missions": self.post_missions,
            "/api/projects": self.post_projects,
            "/api/scan": self.post_scan,
            "/api/priorities": self.post_priorities,
            "/api/intake": self.post_intake,
            "/api/sync": self.post_sync,
        }

    def dispatch_get(self, path: str, params: dict[str, list[str]]) -> Any:
        """Route a GET request.

        Args:
            path: URL path.
            params: Parsed query string.

        Returns:
            The data half of the success envelope.

        Raises:
            ApiError: 404 on an unknown route.
        """
        handler = self.get_routes.get(path)
        if handler is None:
            raise ApiError(404, f"no such route: {path}")
        return handler(params)

    def dispatch_post(self, path: str, body: dict[str, Any]) -> Any:
        """Route a POST request.

        Args:
            path: URL path.
            body: Decoded JSON body.

        Returns:
            The data half of the success envelope.

        Raises:
            ApiError: 404 on an unknown route.
        """
        handler = self.post_routes.get(path)
        if handler is None:
            raise ApiError(404, f"no such route: {path}")
        return handler(body)

    # ------------------------------------------------------------ GET handlers

    def health(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Liveness plus whether the state tree is set up.

        Args:
            params: Parsed query string.

        Returns:
            {dave_home, schema_version, setup}.
        """
        config_path = Path(self.dave_home) / "config.json"
        state = self.reader.state()
        return {
            "dave_home": self.dave_home,
            "schema_version": state.get("schema_version"),
            "setup": config_path.is_file(),
        }

    def overview(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """The composite the header and Overview view are built from.

        Args:
            params: Parsed query string.

        Returns:
            The overview object described in the API contract.
        """
        cfg = self.reader.config(redact=False)
        state = self.reader.state()
        priorities = self.reader.priorities()
        focus = state.get("focus")
        notes = self.reader.notes()
        horizon = _dig(cfg, ("review", "promise_horizon_days"), 3)
        horizon_date = (date.today() + timedelta(days=int(horizon))).isoformat()
        due_soon = [
            c for c in self.reader.commitments()
            if c.get("status") == "open" and c.get("due", "9999") <= horizon_date
        ]
        focus_ref = focus.get("ref") if isinstance(focus, dict) else None
        return {
            "user": cfg.get("user", {}),
            "personality": cfg.get("personality", {}),
            "priorities_config": {
                "max_now": _dig(cfg, ("priorities", "max_now"), 3),
                "drift_threshold_minutes": _dig(
                    cfg, ("priorities", "drift_threshold_minutes"), 45),
            },
            "focus": focus,
            "focus_stack": state.get("focus_stack", []),
            "focus_minutes": iso_minutes(
                focus.get("started") if isinstance(focus, dict) else None),
            "on_list": bool(focus_ref) and focus_ref in priorities["raw"],
            "next_note": (notes.get(focus_ref) or {}).get("text")
            if focus_ref else None,
            "active_mission": state.get("active_mission"),
            "last_intake": state.get("last_intake"),
            "last_brief": state.get("last_brief"),
            "priorities": priorities,
            "today": self.reader.logs(1)[0]
            if self.reader.logs(1) else {"date": date.today().isoformat(),
                                         "entries": []},
            "parked_open_count": len(self.reader.parking()["open"]),
            "promises_due_soon": due_soon,
            "open_charges_count": sum(
                1 for r in self.reader.assignment_rows() if r["verdict"] is None),
            "sync_enabled": bool(_dig(cfg, ("sync", "enabled"), False)),
        }

    def priorities(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Parsed priorities.md plus the raw text.

        Args:
            params: Parsed query string.

        Returns:
            The parsed priorities object.
        """
        return self.reader.priorities()

    def time(self, params: dict[str, list[str]]) -> Any:
        """Time ledger, optionally filtered.

        Args:
            params: ref, project, since query params.

        Returns:
            The `time --json` payload.
        """
        return self.cli.time_json(
            ref=params.get("ref", [None])[0] or None,
            project=params.get("project", [None])[0] or None,
            since=params.get("since", [None])[0] or None,
        )

    def missions(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Mission list merged with assignment rows; one brief on ?slug=.

        Args:
            params: Optional slug query param.

        Returns:
            {missions, assignments, brief?}.
        """
        listed = self.cli.mission_list_json()
        meta = self.reader.missions()
        rows = self.reader.assignment_rows()
        by_mission: dict[str, list[dict[str, Any]]] = {}
        for row in rows:
            by_mission.setdefault(row["mission"], []).append(row)
        seen = {m.get("slug", "") for m in listed}
        missions = []
        for m in listed:
            slug = m.get("slug", "")
            mrows = by_mission.get(slug, [])
            missions.append({
                **m,
                "meta": meta.get(slug, {}),
                "assignments": mrows,
                "open_count": sum(1 for r in mrows if r["verdict"] is None),
            })
        # missions.json is the registry; a mission registered without a brief
        # file on disk is still a mission — mark it rather than dropping it.
        for slug, mmeta in sorted(meta.items()):
            if slug in seen:
                continue
            mrows = by_mission.get(slug, [])
            missions.append({
                "slug": slug,
                "project": mmeta.get("project", ""),
                "ref": mmeta.get("ref", ""),
                "status": mmeta.get("status", "open"),
                "opened": mmeta.get("opened", ""),
                "meta": mmeta,
                "assignments": mrows,
                "open_count": sum(1 for r in mrows if r["verdict"] is None),
                "brief_missing": True,
            })
        result: dict[str, Any] = {"missions": missions}
        slug = params.get("slug", [None])[0]
        if slug:
            result["slug"] = slug
            if slug in seen:
                result["brief"] = self.cli.mission_show(slug)
            else:
                # No brief file: `mission show` would die, so say so here.
                result["brief"] = None
                result["brief_missing"] = True
        return result

    def assignments(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """All assignment rows plus per-agent roster statistics.

        Args:
            params: Parsed query string.

        Returns:
            {rows, roster: {agent: {total, open, by_verdict, models}}}.
        """
        rows = self.reader.assignment_rows()
        cfg = self.reader.config(redact=False)
        roster: dict[str, dict[str, Any]] = {}
        # Configured agents exist even with zero charges — a roster that only
        # lists agents already used hides most of who can be delegated to.
        for agent, model in (cfg.get("models") or {}).items():
            roster[agent] = {"total": 0, "open": 0, "by_verdict": {},
                             "models": [], "default_model": model,
                             "enabled": bool(
                                 (cfg.get("roster") or {}).get(agent, True))}
        for agent, enabled in (cfg.get("roster") or {}).items():
            stat = roster.setdefault(
                agent, {"total": 0, "open": 0, "by_verdict": {},
                        "models": [], "default_model": None})
            stat["enabled"] = bool(enabled)
        for row in rows:
            agent = row["agent"] or "(unknown)"
            stat = roster.setdefault(
                agent, {"total": 0, "open": 0, "by_verdict": {}, "models": [],
                        "default_model": None, "enabled": True})
            stat["total"] += 1
            if row["verdict"] is None:
                stat["open"] += 1
            else:
                stat["by_verdict"][row["verdict"]] = (
                    stat["by_verdict"].get(row["verdict"], 0) + 1)
            if row["model"] and row["model"] not in stat["models"]:
                stat["models"].append(row["model"])
        return {"rows": rows, "roster": roster}

    def projects(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Registered projects merged with scan state.

        Args:
            params: fresh=1 re-probes git state first.

        Returns:
            {projects, scanned_at}.
        """
        if params.get("fresh", [None])[0] == "1":
            self.cli.scan_json(fresh=True)
        registered = self.reader.projects()
        entries = self.reader.scan_cache().get("entries", {})
        generated = self.reader.scan_cache().get("generated")
        merged = [{**p, "scan": entries.get(p.get("slug", ""), {})}
                  for p in registered]
        return {"projects": merged, "scanned_at": generated}

    def review(self, params: dict[str, list[str]]) -> Any:
        """The weekly sweep.

        Args:
            params: days query param.

        Returns:
            The `review --json` payload.
        """
        return self.cli.review_json(days=_days(params))

    def drift(self, params: dict[str, list[str]]) -> Any:
        """Drift events within a window.

        Args:
            params: days query param.

        Returns:
            The `drift events --json` payload.
        """
        return self.cli.drift_events_json(days=_days(params))

    def promises(self, params: dict[str, list[str]]) -> Any:
        """All commitments.

        Args:
            params: Parsed query string.

        Returns:
            The `promise list --json` payload.
        """
        return self.cli.promise_list_json()

    def parked(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """The parking lot, open and retired.

        Args:
            params: Parsed query string.

        Returns:
            The parsed parking lot.
        """
        return self.reader.parking()

    def log(self, params: dict[str, list[str]]) -> list[dict[str, Any]]:
        """Day logs for a window.

        Args:
            params: days query param.

        Returns:
            The parsed day logs.
        """
        return self.reader.logs(days=_days(params))

    def notes(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Next-action notes by ref.

        Args:
            params: Parsed query string.

        Returns:
            The notes object.
        """
        return self.reader.notes()

    def intake(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Archived intake boards: the list, or one file on ?file=.

        Args:
            params: Optional file query param (basename only).

        Returns:
            {files} or {file, content}.

        Raises:
            ApiError: 400 on a path part, 404 on an unknown file.
        """
        name = params.get("file", [None])[0]
        if name is None:
            return {"files": self.reader.intake_files()}
        if Path(name).name != name:
            raise ApiError(400, "file must be a plain filename")
        content = self.reader.intake_file(name)
        if content is None:
            raise ApiError(404, f"no such intake file: {name}")
        return {"file": name, "content": content}

    def sync(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """Sync status. Can take ~15s when the remote is slow.

        Args:
            params: Parsed query string.

        Returns:
            {output, enabled}.
        """
        return {
            "output": self.cli.sync_status(),
            "enabled": bool(_dig(self.reader.config(redact=False),
                                 ("sync", "enabled"), False)),
        }

    def config(self, params: dict[str, list[str]]) -> dict[str, Any]:
        """config.json with credential-shaped values masked.

        Args:
            params: Parsed query string.

        Returns:
            The redacted config object.
        """
        return self.reader.config(redact=True)

    # ----------------------------------------------------------- POST handlers

    def post_focus(self, body: dict[str, Any]) -> dict[str, Any]:
        """Set, push, pop, or clear the focus.

        Args:
            body: {action: set|push|pop|clear, ref?, label?}.

        Returns:
            {output} plus the refreshed focus fields.
        """
        action = _one_of(body, "action", ("set", "push", "pop", "clear"))
        if action in ("set", "push"):
            _require(body, "ref")
        output = self.cli.focus(action, body.get("ref"), body.get("label"))
        state = self.reader.state()
        return {"output": output, "focus": state.get("focus"),
                "focus_stack": state.get("focus_stack", [])}

    def post_next(self, body: dict[str, Any]) -> dict[str, Any]:
        """Set or clear a ref's next note.

        Args:
            body: {action: set|clear, ref, text?}.

        Returns:
            {output, notes}.
        """
        action = _one_of(body, "action", ("set", "clear"))
        _require(body, "ref")
        if action == "set":
            _require(body, "text")
            output = self.cli.next_set(body["ref"], body["text"])
        else:
            output = self.cli.next_clear(body["ref"])
        return {"output": output, "notes": self.reader.notes()}

    def post_log(self, body: dict[str, Any]) -> dict[str, Any]:
        """Append a line to today's log.

        Args:
            body: {text}.

        Returns:
            {output, today}.
        """
        _require(body, "text")
        output = self.cli.log(body["text"])
        days = self.reader.logs(1)
        return {"output": output,
                "today": days[0] if days else {"entries": []}}

    def post_park(self, body: dict[str, Any]) -> dict[str, Any]:
        """Capture a parked item.

        Args:
            body: {text}.

        Returns:
            {output, parked}.
        """
        _require(body, "text")
        output = self.cli.park(body["text"])
        return {"output": output, "parked": self.reader.parking()}

    def post_parked_done(self, body: dict[str, Any]) -> dict[str, Any]:
        """Retire the n-th open parked item.

        Args:
            body: {index}.

        Returns:
            {output, parked}.

        Raises:
            ApiError: 400 on a non-integer index.
        """
        _require(body, "index")
        try:
            index = int(body["index"])
        except (TypeError, ValueError) as exc:
            raise ApiError(400, "index must be a number") from exc
        output = self.cli.parked_done(index)
        return {"output": output, "parked": self.reader.parking()}

    def post_promise(self, body: dict[str, Any]) -> dict[str, Any]:
        """Add, keep, miss, or move a commitment.

        Args:
            body: {action, who?, what?, due?, ref?, project?, id?}.

        Returns:
            {output, promises}.
        """
        action = _one_of(body, "action", ("add", "keep", "miss", "move"))
        if action == "add":
            _require(body, "who", "what", "due")
            output = self.cli.promise_add(
                body["who"], body["what"], body["due"],
                ref=body.get("ref"), project=body.get("project"))
        elif action == "move":
            _require(body, "id", "due")
            output = self.cli.promise_move(body["id"], body["due"])
        else:
            _require(body, "id")
            output = self.cli.promise_close(action, body["id"])
        return {"output": output, "promises": self.cli.promise_list_json()}

    def post_drift_record(self, body: dict[str, Any]) -> dict[str, Any]:
        """Log a resolved drift episode.

        Args:
            body: {kind, outcome, ref?, project?}.

        Returns:
            {output}.
        """
        kind = _one_of(body, "kind", DRIFT_KINDS)
        outcome = _one_of(body, "outcome", DRIFT_OUTCOMES)
        output = self.cli.drift_record(
            kind, outcome, ref=body.get("ref"), project=body.get("project"))
        return {"output": output}

    def post_missions(self, body: dict[str, Any]) -> dict[str, Any]:
        """Create, open, close, assign on, or grade a mission.

        Args:
            body: {action, name?, slug?, project?, ref?, outcome?, agent?,
                   charge?, model?, id?, verdict?, summary?}.

        Returns:
            {output} plus the refreshed mission list.
        """
        action = _one_of(body, "action",
                         ("new", "open", "close", "assign", "record"))
        if action == "new":
            _require(body, "name")
            output = self.cli.mission_new(
                body["name"], project=body.get("project"), ref=body.get("ref"))
        elif action == "open":
            _require(body, "slug")
            output = self.cli.mission_open(body["slug"])
        elif action == "close":
            _require(body, "slug")
            output = self.cli.mission_close(body["slug"], body.get("outcome"))
        elif action == "assign":
            _require(body, "slug", "agent", "charge")
            output = self.cli.mission_assign(
                body["slug"], body["agent"], body["charge"],
                model=body.get("model"), ref=body.get("ref"))
        else:
            _require(body, "id")
            verdict = _one_of(body, "verdict", MISSION_VERDICTS)
            output = self.cli.mission_record(
                body["id"], verdict, summary=body.get("summary"))
        return {"output": output, "missions": self.missions({})["missions"]}

    def post_projects(self, body: dict[str, Any]) -> dict[str, Any]:
        """Register or update a project.

        Args:
            body: {action, path?, slug?, name?, cadence?, goal?, status?, ref?}.

        Returns:
            {output} plus the refreshed project list.
        """
        action = _one_of(body, "action",
                         ("add", "status", "link", "unlink", "touch"))
        if action == "add":
            _require(body, "path")
            cadence = body.get("cadence")
            if cadence is not None and cadence not in PROJECT_CADENCES:
                raise ApiError(
                    400, f"cadence must be one of: {', '.join(PROJECT_CADENCES)}")
            output = self.cli.project_add(
                body["path"], name=body.get("name"),
                cadence=cadence, goal=body.get("goal"))
        elif action == "status":
            _require(body, "slug")
            status = _one_of(body, "status", PROJECT_STATUSES)
            output = self.cli.project_status(body["slug"], status)
        elif action in ("link", "unlink"):
            _require(body, "slug", "ref")
            output = self.cli.project_link(
                body["slug"], body["ref"], unlink=(action == "unlink"))
        else:
            _require(body, "slug")
            output = self.cli.project_touch(body["slug"])
        return {"output": output, "projects": self.projects({})["projects"]}

    def post_scan(self, body: dict[str, Any]) -> dict[str, Any]:
        """Re-probe git state across all projects.

        Args:
            body: Ignored.

        Returns:
            {output} plus the refreshed projects.
        """
        scan = self.cli.scan_json(fresh=True)
        return {"output": json.dumps(scan), "scan": scan,
                "projects": self.projects({})["projects"]}

    def post_priorities(self, body: dict[str, Any]) -> dict[str, Any]:
        """Replace priorities.md from the editor.

        Args:
            body: {markdown}.

        Returns:
            {output} plus the re-parsed priorities.
        """
        _require(body, "markdown")
        output = self.cli.priorities_set(body["markdown"])
        return {"output": output, "priorities": self.reader.priorities()}

    def post_intake(self, body: dict[str, Any]) -> dict[str, Any]:
        """Archive a pasted board.

        Args:
            body: {source, text}.

        Returns:
            {output} — the archived file's path.
        """
        _require(body, "source", "text")
        output = self.cli.intake(body["source"], body["text"])
        return {"output": output, "files": self.reader.intake_files()}

    def post_sync(self, body: dict[str, Any]) -> dict[str, Any]:
        """Pull or push the state tree.

        Args:
            body: {action: pull|push}. Push is only ever a user click.

        Returns:
            {output}.
        """
        action = _one_of(body, "action", ("pull", "push"))
        output = self.cli.sync(action)
        return {"output": output}


def _dig(obj: dict[str, Any], path: tuple[str, ...], default: Any) -> Any:
    """Walk a nested dict, returning a default on any miss.

    Args:
        obj: The object to walk.
        path: Key path.
        default: Value on miss.

    Returns:
        The nested value, or default.
    """
    cur: Any = obj
    for key in path:
        if not isinstance(cur, dict):
            return default
        cur = cur.get(key)
        if cur is None:
            return default
    return cur
