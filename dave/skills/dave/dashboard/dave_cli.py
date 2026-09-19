"""Typed wrapper around the dave.sh state-layer script.

Every write the dashboard offers goes through this class, so dave.sh stays the
only writer into DAVE_HOME. Arguments are always passed as a list — no shell
strings are ever built here.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any


class DaveError(Exception):
    """A non-zero exit from dave.sh.

    Attributes:
        code: Process exit code (3 = not set up, 4 = needs migrate).
        stderr: Captured standard error, verbatim.
    """

    def __init__(self, code: int, stderr: str) -> None:
        """Store the exit code and stderr for the API layer to map.

        Args:
            code: Process exit code.
            stderr: Captured standard error.
        """
        super().__init__(stderr.strip() or f"dave.sh exited {code}")
        self.code = code
        self.stderr = stderr


class DaveCli:
    """Runs dave.sh subcommands against a given DAVE_HOME."""

    def __init__(self, dave_sh: str | Path, dave_home: str | Path) -> None:
        """Bind the wrapper to a script path and a state directory.

        Args:
            dave_sh: Absolute path to dave.sh.
            dave_home: Absolute path to the state tree.
        """
        self.dave_sh = str(dave_sh)
        self.dave_home = str(dave_home)

    def run(self, *args: str, stdin: str | None = None) -> str:
        """Run dave.sh and return its stdout.

        Args:
            *args: Subcommand and arguments, each a separate argv entry.
            stdin: Optional text fed to the process on standard input.

        Returns:
            Captured standard output.

        Raises:
            DaveError: On non-zero exit or a 30-second timeout.
        """
        env = dict(os.environ, DAVE_HOME=self.dave_home)
        try:
            proc = subprocess.run(
                ["bash", self.dave_sh, *args],
                input=stdin,
                capture_output=True,
                text=True,
                timeout=30,
                env=env,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise DaveError(-1, "dave.sh timed out after 30s") from exc
        if proc.returncode != 0:
            raise DaveError(proc.returncode, proc.stderr)
        return proc.stdout

    def run_json(self, *args: str) -> Any:
        """Run a --json subcommand and parse its stdout.

        Args:
            *args: Subcommand and arguments.

        Returns:
            The decoded JSON value.

        Raises:
            DaveError: On non-zero exit or unparseable output.
        """
        out = self.run(*args)
        try:
            return json.loads(out)
        except json.JSONDecodeError as exc:
            raise DaveError(-1, f"dave.sh returned invalid JSON: {exc}") from exc

    # ------------------------------------------------------------------ reads

    def time_json(
        self,
        ref: str | None = None,
        project: str | None = None,
        since: str | None = None,
    ) -> Any:
        """Recorded time segments plus the currently open one.

        Args:
            ref: Optional ref filter.
            project: Optional project filter.
            since: Optional start date.

        Returns:
            The `time --json` payload.
        """
        args = ["time", "--json"]
        if ref:
            args.append(ref)
        if project:
            args += ["--project", project]
        if since:
            args += ["--since", since]
        return self.run_json(*args)

    def promise_list_json(self, open_only: bool = False) -> Any:
        """Commitments as JSON.

        Args:
            open_only: Restrict to open commitments.

        Returns:
            The `promise list --json` payload.
        """
        args = ["promise", "list", "--json"]
        if open_only:
            args.append("--open")
        return self.run_json(*args)

    def mission_list_json(self) -> Any:
        """All missions as JSON.

        Returns:
            The `mission list --json` payload.
        """
        return self.run_json("mission", "list", "--json")

    def mission_show(self, slug: str) -> str:
        """One mission brief rendered as markdown.

        Args:
            slug: Mission slug.

        Returns:
            The `mission show` text.
        """
        return self.run("mission", "show", slug)

    def project_list_json(self) -> Any:
        """Registered projects as JSON.

        Returns:
            The `project list --json` payload.
        """
        return self.run_json("project", "list", "--json")

    def scan_json(self, fresh: bool = False) -> Any:
        """Git state across projects as JSON.

        Args:
            fresh: Bypass the scan cache and re-probe.

        Returns:
            The `scan --json` payload.
        """
        args = ["scan", "--json"]
        if fresh:
            args.append("--fresh")
        return self.run_json(*args)

    def review_json(self, days: int = 7) -> Any:
        """The weekly sweep as JSON.

        Args:
            days: Window length in days.

        Returns:
            The `review --json` payload.
        """
        return self.run_json("review", "--days", str(days), "--json")

    def drift_events_json(self, days: int = 7) -> Any:
        """Drift events within a window as JSON.

        Args:
            days: Window length in days.

        Returns:
            The `drift events --json` payload.
        """
        return self.run_json("drift", "events", "--days", str(days), "--json")

    def sync_status(self) -> str:
        """Ahead/behind/dirty versus the remote.

        Returns:
            The `sync status` text.
        """
        return self.run("sync", "status")

    # ----------------------------------------------------------------- writes

    def focus(self, action: str, ref: str | None = None, label: str | None = None) -> str:
        """Run a focus subcommand.

        Args:
            action: One of set, push, pop, clear.
            ref: Ref for set/push.
            label: Optional label for set/push.

        Returns:
            The dave.sh output line.
        """
        args = ["focus", action]
        if action in ("set", "push"):
            args.append(ref or "")
            if label:
                args.append(label)
        return self.run(*args)

    def next_set(self, ref: str, text: str) -> str:
        """Record where a ref was left off.

        Args:
            ref: The ref.
            text: The note.

        Returns:
            The dave.sh output line.
        """
        return self.run("next", "set", ref, text)

    def next_clear(self, ref: str) -> str:
        """Clear a ref's next note.

        Args:
            ref: The ref.

        Returns:
            The dave.sh output line.
        """
        return self.run("next", "clear", ref)

    def log(self, text: str) -> str:
        """Append a timestamped line to today's log.

        Args:
            text: The log text.

        Returns:
            The dave.sh output line.
        """
        return self.run("log", text)

    def park(self, text: str) -> str:
        """Capture a detour in the parking lot.

        Args:
            text: The parked item text.

        Returns:
            The dave.sh output line.
        """
        return self.run("park", text)

    def parked_done(self, index: int) -> str:
        """Retire the n-th open parked item.

        Args:
            index: 1-based position among open items.

        Returns:
            The dave.sh output line.
        """
        return self.run("parked", "done", str(index))

    def promise_add(
        self,
        who: str,
        what: str,
        due: str,
        ref: str | None = None,
        project: str | None = None,
    ) -> str:
        """Record a commitment.

        Args:
            who: Who it was made to.
            what: What was promised.
            due: Due date, anything `date` understands.
            ref: Optional linked ref.
            project: Optional linked project.

        Returns:
            The dave.sh output line.
        """
        args = ["promise", "add", who, what, due]
        if ref:
            args += ["--ref", ref]
        if project:
            args += ["--project", project]
        return self.run(*args)

    def promise_close(self, action: str, promise_id: str) -> str:
        """Close a commitment as kept or missed.

        Args:
            action: keep or miss.
            promise_id: The commitment id.

        Returns:
            The dave.sh output line.
        """
        return self.run("promise", action, promise_id)

    def promise_move(self, promise_id: str, due: str) -> str:
        """Renegotiate a commitment's date.

        Args:
            promise_id: The commitment id.
            due: New due date.

        Returns:
            The dave.sh output line.
        """
        return self.run("promise", "move", promise_id, due)

    def drift_record(
        self,
        kind: str,
        outcome: str,
        ref: str | None = None,
        project: str | None = None,
    ) -> str:
        """Log a resolved drift episode.

        Args:
            kind: Drift kind.
            outcome: Resolution outcome.
            ref: Optional ref.
            project: Optional project.

        Returns:
            The dave.sh output line.
        """
        args = ["drift", "record", kind, outcome]
        if ref:
            args += ["--ref", ref]
        if project:
            args += ["--project", project]
        return self.run(*args)

    def mission_new(
        self,
        name: str,
        project: str | None = None,
        ref: str | None = None,
    ) -> str:
        """Create a mission brief.

        Args:
            name: Mission name.
            project: Optional project slug.
            ref: Optional ref.

        Returns:
            The new brief's path.
        """
        args = ["mission", "new", name]
        if project:
            args += ["--project", project]
        if ref:
            args += ["--ref", ref]
        return self.run(*args)

    def mission_open(self, slug: str) -> str:
        """Make a mission the active one.

        Args:
            slug: Mission slug.

        Returns:
            The dave.sh output line.
        """
        return self.run("mission", "open", slug)

    def mission_close(self, slug: str, outcome: str | None = None) -> str:
        """Close a mission.

        Args:
            slug: Mission slug.
            outcome: Optional outcome text.

        Returns:
            The dave.sh output line.
        """
        args = ["mission", "close", slug]
        if outcome:
            args += ["--outcome", outcome]
        return self.run(*args)

    def mission_assign(
        self,
        slug: str,
        agent: str,
        charge: str,
        model: str | None = None,
        ref: str | None = None,
    ) -> str:
        """Record a delegation to an agent.

        Args:
            slug: Mission slug.
            agent: Agent name.
            charge: The charge text.
            model: Optional model override.
            ref: Optional ref.

        Returns:
            The new assignment id.
        """
        args = ["mission", "assign", slug, agent, charge]
        if model:
            args += ["--model", model]
        if ref:
            args += ["--ref", ref]
        return self.run(*args)

    def mission_record(
        self,
        assignment_id: str,
        verdict: str,
        summary: str | None = None,
    ) -> str:
        """Grade a returned charge.

        Args:
            assignment_id: The assignment id.
            verdict: One of trust, partial, rerun, discard.
            summary: Optional summary.

        Returns:
            The dave.sh output line.
        """
        args = ["mission", "record", assignment_id, "--verdict", verdict]
        if summary:
            args += ["--summary", summary]
        return self.run(*args)

    def project_add(
        self,
        path: str,
        name: str | None = None,
        cadence: str | None = None,
        goal: str | None = None,
    ) -> str:
        """Register a project.

        Args:
            path: Project directory.
            name: Optional display name.
            cadence: Optional cadence.
            goal: Optional goal text.

        Returns:
            The dave.sh output line.
        """
        args = ["project", "add", path]
        if name:
            args += ["--name", name]
        if cadence:
            args += ["--cadence", cadence]
        if goal:
            args += ["--goal", goal]
        return self.run(*args)

    def project_status(self, slug: str, status: str) -> str:
        """Change a project's status.

        Args:
            slug: Project slug.
            status: New status.

        Returns:
            The dave.sh output line.
        """
        return self.run("project", "status", slug, status)

    def project_link(self, slug: str, ref: str, unlink: bool = False) -> str:
        """Attach or detach a ref on a project.

        Args:
            slug: Project slug.
            ref: The ref.
            unlink: Remove rather than add the link.

        Returns:
            The dave.sh output line.
        """
        return self.run("project", "unlink" if unlink else "link", slug, ref)

    def project_touch(self, slug: str) -> str:
        """Stamp a project's last activity.

        Args:
            slug: Project slug.

        Returns:
            The dave.sh output line.
        """
        return self.run("project", "touch", slug)

    def priorities_set(self, markdown: str) -> str:
        """Replace priorities.md wholesale.

        Args:
            markdown: The new file contents.

        Returns:
            The dave.sh output line.
        """
        return self.run("priorities", "set", stdin=markdown)

    def intake(self, source: str, text: str) -> str:
        """Archive a pasted board.

        Args:
            source: Board/source name.
            text: The raw board text.

        Returns:
            The archived file's path.
        """
        return self.run("intake", source, stdin=text)

    def sync(self, action: str) -> str:
        """Pull or push the state tree.

        Args:
            action: pull or push. Push reaches here only via a user click.

        Returns:
            The dave.sh output line.
        """
        return self.run("sync", action)
