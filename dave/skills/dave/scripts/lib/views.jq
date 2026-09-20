# views.jq — fold the event journal into the derived views.
#
# Entity identity is part of the event contract. New creation events carry an
# opaque entity_id; old creation events receive a deterministic identity derived
# from their envelope (or from their position in an import.snapshot). Mutations
# written by old clients are resolved by display alias only when that alias is
# unique. An ambiguous old mutation is retained in diagnostics and is never
# guessed onto the device that emitted it.

def mission_default($opened):
  {project:"", ref:"", status:"open", opened:$opened, closed:null, outcome:null};

def opened_of($d): ($d.opened // (($d.ts // "")[0:10]));

def event_id($e): (($e.dev // "") + ":" + (($e.seq // 0) | tostring));

def legacy_entity_id($e;$kind;$position):
  ("legacy:" + ($e.dev // "unknown") + ":" + (($e.seq // 0) | tostring)
   + ":" + $kind + ":" + (($position // 0) | tostring));

def entity_for($d;$e;$kind;$position):
  if (($d.entity_id // "") | length) > 0 then $d.entity_id
  else legacy_entity_id($e;$kind;$position) end;

def promise_creation($x):
  {who:($x.who // ""), what:($x.what // ""), due:($x.due // ""),
   ref:($x.ref // ""), project:($x.project // "")};

def assignment_creation($x):
  {mission:($x.mission // ""), agent:($x.agent // ""),
   charge:($x.charge // ""), model:($x.model // ""),
   ref:($x.ref // ""), project:($x.project // "")};

def identity_diagnostic($e;$d;$kind;$candidates):
  {event_id:event_id($e), event_type:($e.type // ""), entity_type:$kind,
   legacy_id:($d.id // ""), candidate_entity_ids:$candidates};

# Build repairs first so a mapping remains effective even if its line sorts
# before the damaged legacy mutation due to a manually supplied timestamp.
(sort_by(.ts, .dev, .seq)) as $evs
| (reduce ($evs[] | select(.type == "entity.repair")) as $r ({};
    if (($r.data.original_event_id // "") != ""
        and (($r.data.entity_id // "") | length) > 0)
    then .[$r.data.original_event_id] = $r.data.entity_id else . end)) as $repairs
| reduce $evs[] as $e (
    {
      state: {focus:null, focus_stack:[], active_mission:null,
              drift_events:[], last_intake:null, last_brief:null,
              created:null},
      missions: {}, notes: {}, commitments: [], sessions: [], assignments: [],
      log: {}, parked: [], projects: {}, imported_created: null,
      identity_diagnostics: {
        ambiguous_legacy_mutations: [], duplicate_entity_ids: [],
        unresolved_repairs: [], invalid_repairs: []
      }
    };
    ($e.type) as $t | ($e.data // {}) as $d
    | if $t == "import.snapshot" then
        # Snapshot positions are stable within the immutable import event.
        ($d.state // {}) as $s
        | .state = (.state + $s)
        | .missions = (.missions + ($d.missions // {}))
        | .notes = (.notes + ($d.notes // {}))
        | .commitments = (.commitments +
            (($d.commitments // []) | to_entries
             | map(.value as $x
                 | ($x + {entity_id:entity_for($x;$e;"promise";.key),
                         legacy_alias:($x.legacy_alias // $x.id)}))))
        | .sessions = (.sessions + ($d.sessions // []))
        | .assignments = (.assignments +
            (($d.assignments // []) | to_entries
             | map(.value as $x
                 | ($x + {entity_id:entity_for($x;$e;"assignment";.key),
                         legacy_alias:($x.legacy_alias // $x.id)}))))
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
        (entity_for($d;$e;"promise";0)) as $eid
        | ($d + {entity_id:$eid, legacy_alias:($d.legacy_alias // $d.id)}) as $item
        | ([.commitments[] | select(.entity_id == $eid)] | first) as $old
        | if $old != null then
            if (promise_creation($old) != promise_creation($item)) then
              .identity_diagnostics.duplicate_entity_ids +=
                [{entity_id:$eid, event_id:event_id($e),
                  existing:promise_creation($old), incoming:promise_creation($item)}]
            else . end
          else
            ([.commitments[]
              | select((.legacy_alias // .id // "") == ($item.legacy_alias // $item.id // ""))]
             | length) as $same_alias
            | (if $same_alias == 0 then $item
               else $item + {id:(($item.id // "") + "~" + ($e.dev // "legacy")
                    + (if $same_alias > 1 then "~" + (($same_alias + 1)|tostring) else "" end))}
               end) as $stored
            | .commitments += [$stored]
          end
      elif $t == "promise.keep" or $t == "promise.miss" then
        ([.commitments[]
          | select(if (($d.entity_id // "") | length) > 0
                   then .entity_id == $d.entity_id
                   elif ($repairs[event_id($e)] // "") != ""
                   then .entity_id == $repairs[event_id($e)]
                   else ((.legacy_alias // .id // "") == ($d.id // "")
                         or (.id // "") == ($d.id // "")) end)]) as $targets
        | ([ $evs[] | select(.type == "promise.add"
                              and (($d.id // "") == (.data.id // "")))
              | entity_for(.data;.;"promise";0) ] | unique) as $legacy_candidates
        | if ($targets | length) == 1
             and ((($d.entity_id // "") | length) > 0
                  or (($repairs[event_id($e)] // "") != "")
                  or (($legacy_candidates | length) <= 1)) then
            .commitments |= map(if .entity_id == $targets[0].entity_id
              then .status = $d.status | .closed = ($d.ts // $e.ts) else . end)
          elif (($legacy_candidates | length) > 1 or ($targets | length) > 1)
               and (($d.entity_id // "") | length) == 0
               and (($repairs[event_id($e)] // "") == "") then
            .identity_diagnostics.ambiguous_legacy_mutations +=
              [identity_diagnostic($e;$d;"promise";
                (($legacy_candidates + [$targets[].entity_id]) | unique))]
          elif (($d.entity_id // "") | length) > 0
               and (($targets | length) == 0) then
            .identity_diagnostics.unresolved_repairs +=
              [identity_diagnostic($e;$d;"promise";[])]
          elif (($repairs[event_id($e)] // "") != "") and (($targets | length) == 0) then
            .identity_diagnostics.unresolved_repairs +=
              [identity_diagnostic($e;$d;"promise";[])]
          else . end
      elif $t == "promise.move" then
        ([.commitments[]
          | select(if (($d.entity_id // "") | length) > 0
                   then .entity_id == $d.entity_id
                   elif ($repairs[event_id($e)] // "") != ""
                   then .entity_id == $repairs[event_id($e)]
                   else ((.legacy_alias // .id // "") == ($d.id // "")
                         or (.id // "") == ($d.id // "")) end)]) as $targets
        | ([ $evs[] | select(.type == "promise.add"
                              and (($d.id // "") == (.data.id // "")))
              | entity_for(.data;.;"promise";0) ] | unique) as $legacy_candidates
        | if ($targets | length) == 1
             and ((($d.entity_id // "") | length) > 0
                  or (($repairs[event_id($e)] // "") != "")
                  or (($legacy_candidates | length) <= 1)) then
            .commitments |= map(if .entity_id == $targets[0].entity_id
              then .moved = ((.moved // []) + [.due]) | .due = $d.due else . end)
          elif (($legacy_candidates | length) > 1 or ($targets | length) > 1)
               and (($d.entity_id // "") | length) == 0
               and (($repairs[event_id($e)] // "") == "") then
            .identity_diagnostics.ambiguous_legacy_mutations +=
              [identity_diagnostic($e;$d;"promise";
                (($legacy_candidates + [$targets[].entity_id]) | unique))]
          elif (($d.entity_id // "") | length) > 0 then
            .identity_diagnostics.unresolved_repairs +=
              [identity_diagnostic($e;$d;"promise";[])]
          else . end
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
      elif $t == "mission.assign" then
        (entity_for($d;$e;"assignment";0)) as $eid
        | ($d + {entity_id:$eid, type:($d.type // "assign"),
                 legacy_alias:($d.legacy_alias // $d.id)}) as $item
        | ([.assignments[] | select(.entity_id == $eid)] | first) as $old
        | if $old != null then
            if (assignment_creation($old) != assignment_creation($item)) then
              .identity_diagnostics.duplicate_entity_ids +=
                [{entity_id:$eid, event_id:event_id($e),
                  existing:assignment_creation($old), incoming:assignment_creation($item)}]
            else . end
          else
            ([.assignments[]
              | select((.legacy_alias // .id // "") == ($item.legacy_alias // $item.id // ""))]
             | length) as $same_alias
            | (if $same_alias == 0 then $item
               else $item + {id:(($item.id // "") + "~" + ($e.dev // "legacy")
                    + (if $same_alias > 1 then "~" + (($same_alias + 1)|tostring) else "" end))}
               end) as $stored
            | .assignments += [$stored]
            | .missions[$stored.mission] = (.missions[$stored.mission]
                // mission_default(opened_of($stored)))
          end
      elif $t == "mission.grade" then
        ([.assignments[]
          | select(if (($d.entity_id // "") | length) > 0
                   then .entity_id == $d.entity_id
                   elif ($repairs[event_id($e)] // "") != ""
                   then .entity_id == $repairs[event_id($e)]
                   else ((.legacy_alias // .id // "") == ($d.id // "")
                         or (.id // "") == ($d.id // "")) end)]) as $targets
        | ([ $evs[] | select(.type == "mission.assign"
                              and (($d.id // "") == (.data.id // "")))
              | entity_for(.data;.;"assignment";0) ] | unique) as $legacy_candidates
        | if ($targets | length) == 1
             and ((($d.entity_id // "") | length) > 0
                  or (($repairs[event_id($e)] // "") != "")
                  or (($legacy_candidates | length) <= 1)) then
            .assignments |= map(if .entity_id == $targets[0].entity_id
              then .verdict = $d.verdict | .summary = ($d.summary // "")
                   | .returned = ($d.ts // $e.ts) else . end)
          elif (($legacy_candidates | length) > 1 or ($targets | length) > 1)
               and (($d.entity_id // "") | length) == 0
               and (($repairs[event_id($e)] // "") == "") then
            .identity_diagnostics.ambiguous_legacy_mutations +=
              [identity_diagnostic($e;$d;"assignment";
                (($legacy_candidates + [$targets[].entity_id]) | unique))]
          elif (($d.entity_id // "") | length) > 0
               or (($repairs[event_id($e)] // "") != "") then
            .identity_diagnostics.unresolved_repairs +=
              [identity_diagnostic($e;$d;"assignment";[])]
          else . end
      elif $t == "entity.repair" then
        if (($d.original_event_id // "") == "" or (($d.entity_id // "") | length) == 0) then
          .identity_diagnostics.invalid_repairs += [{event_id:event_id($e), data:$d}]
        else . end
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
| .state.identity_diagnostics = .identity_diagnostics
| .diagnostics = {identity:.identity_diagnostics}
| del(.imported_created)
