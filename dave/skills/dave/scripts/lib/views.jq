# views.jq — fold the event journal into the derived views.
# Run as: jq -s -f views.jq --arg created <ts> --argjson schema_version N
# Input: every event from every journal/*.jsonl as one array.
# Output: {state, missions, notes, commitments, sessions, assignments,
#          log, parked, projects}.
#
# Total order is (ts, dev, seq): identical timestamps resolve by device id,
# then by the per-device counter, so every device folds to the same answer.

def mission_default($opened):
  {project:"", ref:"", status:"open", opened:$opened, closed:null, outcome:null};

def opened_of($d): ($d.opened // (($d.ts // "")[0:10]));

(sort_by(.ts, .dev, .seq)) as $evs
| reduce $evs[] as $e (
    {
      state: {focus:null, focus_stack:[], active_mission:null,
              drift_events:[], last_intake:null, last_brief:null,
              created:null},
      missions: {}, notes: {}, commitments: [], sessions: [], assignments: [],
      log: {}, parked: [], projects: {},
      imported_created: null
    };
    ($e.type) as $t | ($e.data // {}) as $d
    | if $t == "import.snapshot" then
        # A pre-journal tree's files, imported whole. Imported fields override
        # the defaults but not anything the journal has said since.
        ($d.state // {}) as $s
        | .state = (.state + $s)
        | .missions = (.missions + ($d.missions // {}))
        | .notes = (.notes + ($d.notes // {}))
        | .commitments = (.commitments + ($d.commitments // []))
        | .sessions = (.sessions + ($d.sessions // []))
        | .assignments = (.assignments + ($d.assignments // []))
        | .log = (.log + ($d.log // {}))
        | .parked = (.parked + ($d.parked // []))
        | .projects = (.projects + ($d.projects // {}))
        | if $s.created != null then .imported_created = $s.created else . end
      elif $t == "focus.set" then
        .state.focus = {ref:$d.ref, label:$d.label,
                        project:$d.project, started:$d.started}
      elif $t == "focus.push" then
        .state.focus_stack = (.state.focus_stack
            + (if .state.focus == null then [] else [.state.focus] end))
        | .state.focus = {ref:$d.ref, label:$d.label,
                          project:$d.project, started:$d.started}
      elif $t == "focus.pop" then
        # The parent's clock restarts: its earlier time was banked as its own
        # segment when the detour pushed over it.
        if (.state.focus_stack | length) > 0 then
          .state.focus = (.state.focus_stack[-1] | .started = $d.started)
          | .state.focus_stack = .state.focus_stack[:-1]
        else
          .state.focus = null | .state.focus_stack = []
        end
      elif $t == "focus.clear" then
        .state.focus = null | .state.focus_stack = []
      elif $t == "session.close" then
        .sessions += [$d]
      elif $t == "log.add" then
        # data.ts is local wall-clock (with offset); the day file it renders
        # into is the local date, and the line's clock is its HH:MM.
        .log[$d.ts[0:10]] += [{time:$d.ts[11:16], ref:$d.ref, text:$d.text}]
      elif $t == "park.add" then
        .parked += [{id:$d.id, text:$d.text, ref:$d.ref,
                     parked_at:($d.ts[0:10] + " " + $d.ts[11:16]), done:null}]
      elif $t == "park.done" then
        .parked = (.parked | map(
          if .id == $d.id and .done == null then .done = $d.ts[0:10] else . end))
      elif $t == "next.set" then
        .notes[$d.ref] = {text:$d.text, project:$d.project, updated:$d.ts}
      elif $t == "next.clear" then
        .notes = (.notes | del(.[$d.ref]))
      elif $t == "promise.add" then
        # Two devices can mint the same id while offline. The later event — in
        # the deterministic (ts,dev,seq) order — is suffixed with its device id,
        # so single-device ids stay clean and every device converges on the
        # same pair.
        .commitments += [ (if any(.commitments[]; .id == $d.id)
                           then ($d + {id: ($d.id + "~" + $e.dev)}) else $d end) ]
      elif $t == "promise.keep" or $t == "promise.miss" then
        .commitments = (.commitments | map(
          if .id == $d.id then .status = $d.status | .closed = $d.ts else . end))
      elif $t == "promise.move" then
        .commitments = (.commitments | map(
          if .id == $d.id then .moved = ((.moved // []) + [.due]) | .due = $d.due
                           else . end))
      elif $t == "drift.record" then
        .state.drift_events = ((.state.drift_events + [$d]) | .[-500:])
      elif $t == "mission.create" then
        .missions[$d.slug] = ((.missions[$d.slug] // mission_default(opened_of($d)))
          + {project:$d.project, ref:$d.ref, opened:opened_of($d)})
      elif $t == "mission.open" then
        .missions[$d.slug] = (.missions[$d.slug] // mission_default(opened_of($d)))
        | .state.active_mission = $d.slug
      elif $t == "mission.close" then
        .missions[$d.slug] = ((.missions[$d.slug] // mission_default(opened_of($d)))
          + {status:"closed", closed:$d.ts}
          + (if ($d.outcome // "") != "" then {outcome:$d.outcome} else {} end))
        | if .state.active_mission == $d.slug
          then .state.active_mission = null else . end
      elif $t == "mission.assign" or $t == "mission.grade" then
        # Same offline-collision rule as promise.add: a second `m#n` minted
        # elsewhere becomes `m#n~<dev>` in the folded view.
        (if $t == "mission.assign" and any(.assignments[]; .id == $d.id)
         then ($d + {id: ($d.id + "~" + $e.dev)}) else $d end) as $dd
        | .assignments += [$dd]
        # Assigning to an unregistered mission backfills its metadata, the
        # same way _mission_register did on the write path.
        | .missions[$dd.mission] = (.missions[$dd.mission]
            // mission_default(opened_of($dd)))
      elif $t == "project.touch" then
        .projects[$d.slug].last_touched = $d.ts
      elif $t == "project.link" then
        .projects[$d.slug].refs =
          (((.projects[$d.slug].refs // []) + [$d.ref]) | unique)
      elif $t == "project.unlink" then
        .projects[$d.slug].refs =
          ((.projects[$d.slug].refs // []) - [$d.ref])
      elif $t == "brief.seen" then
        .state.last_brief = $d.ts
      elif $t == "intake.archive" then
        .state.last_intake = ($d.ts + " (" + $d.source + ")")
      else . end
  )
| .state.created = (.imported_created // $evs[0].ts // $created)
| .state.schema_version = $schema_version
| del(.imported_created)
