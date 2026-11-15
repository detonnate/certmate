"""Summarize Flutter test events and coverage for review after each run."""

import json
import sys
from pathlib import Path

run = Path(sys.argv[1])
cases = {}
failures = {}
for line in (run / "tests.stdout").read_text().splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if not isinstance(event, dict) or "type" not in event:
        continue
    if event["type"] == "testStart":
        test = event["test"]
        cases[test["id"]] = [test["name"], "incomplete"]
    elif event["type"] == "testDone" and event["testID"] in cases:
        test_id = event["testID"]
        if event["hidden"]:
            cases.pop(test_id)
        else:
            cases[test_id][1] = "skipped" if event["skipped"] else event["result"]
    elif event["type"] == "error":
        failures.setdefault(event["testID"], []).append(event["error"])

output = ["# Test review", "", "## Automated cases", ""]
for test_id, (name, status) in cases.items():
    output.append(f"- **{status}** · {name}")
    for error in failures.get(test_id, []):
        output.append(f"\n```text\n{error}\n```\n")
if not cases:
    output.append("No cases completed. See tests.stderr and summary.txt.")

coverage = run / "lcov.info"
if coverage.exists():
    output += ["", "## Line coverage", ""]
    source = None
    hit = total = 0
    for line in coverage.read_text().splitlines():
        if line.startswith("SF:"):
            source = line[3:]
            hit = total = 0
        elif line.startswith("LH:"):
            hit = int(line[3:])
        elif line.startswith("LF:"):
            total = int(line[3:])
        elif line == "end_of_record" and source and total:
            output.append(f"- {source}: {hit}/{total} ({hit / total:.0%})")

output += ["", "## Device checks", "",
           "See TESTING.md for hardware and OS workflows that require a device.",
           "", "Review failures first, then inspect screenshots and use uncovered "
           "user workflows to choose the next regression cases."]
(run / "review.md").write_text("\n".join(output) + "\n")
