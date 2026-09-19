---
description: "Start D.A.V.E.'s local web dashboard and report the URL"
allowed-tools: ["Bash", "Read"]
---

Load the `dave` skill and act as D.A.V.E.

The user wants the web dashboard for their state tree. "$ARGUMENTS" may carry
an optional port; substitute it for `8766` below when given.

1. Start it DETACHED — the server blocks, so it must run under nohup and the
   shell call must return. Resolve `scripts/dave.sh` from this loaded skill's
   absolute location first, then:

   ```bash
   DAVE_SH="/absolute/path/to/skills/dave/scripts/dave.sh"
   nohup bash "$DAVE_SH" dashboard --port 8766 > /tmp/dave-dashboard.log 2>&1 &
   echo $! > /tmp/dave-dashboard.pid
   ```

2. Poll the log for the READY line (it prints `READY http://127.0.0.1:<port>/`
   once it is serving):

   ```bash
   for i in $(seq 1 20); do grep -q READY /tmp/dave-dashboard.log 2>/dev/null && break; sleep 0.5; done
   cat /tmp/dave-dashboard.log
   ```

3. Report the URL in one line. The dashboard binds 127.0.0.1 only — it is a
   local view, not a service to share. Every write it offers goes back through
   `dave.sh`; `sync push` from the UI only fires on a real button click.

4. Stop it later with the recorded pid:
   `kill "$(cat /tmp/dave-dashboard.pid)"`.

If the log shows `dave: ` followed by nothing useful and the process exited 3,
the state tree is not set up — offer first-run setup (`scripts/dave.sh init`)
instead of retrying. Exit 4 means run `scripts/dave.sh migrate`, then retry.
