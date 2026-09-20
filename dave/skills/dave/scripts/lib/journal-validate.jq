# Validate one journal without emitting private record contents in diagnostics.
def issue($line;$code;$severity):
  {file:$file, line:$line, code:$code, severity:$severity};
def known_type:
  IN("import.snapshot", "focus.set", "focus.push", "focus.pop", "focus.clear",
     "session.close", "next.set", "next.clear", "log.add", "park.add", "park.done",
     "promise.add", "promise.keep", "promise.miss", "promise.move", "drift.record",
     "mission.create", "mission.open", "mission.close", "mission.assign", "mission.grade",
     "project.add", "project.status", "project.link", "project.unlink", "project.touch",
     "project.scan", "intake.archive", "brief.seen", "priorities.set", "entity.repair");
[inputs] as $lines
| [range(0; $lines|length) as $i
   | $lines[$i] as $line | select($line | test("\\S"))
   | (try {event:($line | fromjson)} catch {invalid:true}) as $parsed
   | if $parsed.invalid then
       {issue:issue($i+1; "invalid_json";
         if $i == (($lines|length)-1) and $partial then "warning" else "error" end)}
     elif ($parsed.event | type) != "object" then
       {issue:issue($i+1; "invalid_envelope"; "error")}
     else $parsed.event as $e
       | if (($e.ts | type) != "string" or ($e.dev | type) != "string"
             or ($e.dev | length) == 0 or ($e.seq | type) != "number"
             or $e.seq < 0 or $e.seq != ($e.seq|floor)
             or ($e.type | type) != "string" or ($e.data | type) != "object") then
           {issue:issue($i+1; "invalid_envelope"; "error")}
         elif (($e.version // 1) | IN(1,2) | not) then
           {issue:issue($i+1; "unsupported_event_version"; "error")}
         elif ($e.type | known_type | not) then
           {issue:issue($i+1; "unsupported_event_type"; "error")}
         else {event:$e} end
     end]
| {events:[.[] | select(has("event")) | .event],
   diagnostics:[.[] | select(has("issue")) | .issue]}
