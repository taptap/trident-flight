#!/usr/bin/env python3
"""Exercise actual keyboard and UI input through the local engine's validation protocol."""
import json
from pathlib import Path
import select
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def walk(node):
    yield node
    for child in node.get("children", []):
        yield from walk(child)


def main():
    output = ROOT / ".amp/in"
    output.mkdir(parents=True, exist_ok=True)
    with (output / "interactive-stderr.log").open("w") as errors:
        process = subprocess.Popen([str(ROOT / "tools/run-local.sh"), "run", "-graphicsheadless",
                                    "-validate-interactive", "-x", "1280", "-y", "720"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors, text=True)
        def receive():
            while True:
                if not select.select([process.stdout], [], [], 30)[0]:
                    raise TimeoutError("Engine did not respond within 30 seconds")
                line = process.stdout.readline()
                if not line:
                    raise RuntimeError("Engine exited before sending a response")
                if line.startswith("{"):
                    result = json.loads(line)
                    failures = [e for e in result.get("errors", []) if e.get("category") in ("lua", "resource")]
                    assert not failures, failures
                    return result

        def call(command):
            process.stdin.write(json.dumps(command) + "\n")
            process.stdin.flush()
            return receive()

        def advance(count=1, inputs=None):
            for index in range(count):
                call({"cmd": "step", "dt": 0.05, "input": inputs if index == 0 and inputs else {}})

        def observe():
            return call({"cmd": "observe", "max_depth": 12, "max_children": 120})

        def key(name):
            advance(inputs={"keys_down": [name]})
            advance(3, {"keys_up": [name]})

        def texts(snapshot):
            return [n.get("text", "") for n in walk(snapshot.get("ui", {}))]

        def aircraft(snapshot):
            return next(n for n in walk(snapshot["scene"]) if n.get("name") == "R06")

        def cockpit(snapshot):
            return next(n for n in walk(snapshot["scene"]) if n.get("name") == "Cockpit")

        try:
            assert receive().get("ready")
            advance(4)
            snapshot = observe()
            assert "BLACK EMPEROR" in texts(snapshot)
            target = next(t for t in texts(snapshot) if t.startswith("NEXT 01"))
            assert "190 M" in target, "Initial gate is 190 meters ahead of the aircraft"
            assert not cockpit(snapshot)["enabled"], "Preview must not contain a camera-attached cockpit"
            key("G")
            assert any("起落架放下" in t for t in texts(observe()))
            key("P")
            assert not texts(observe()) or texts(observe()) == [""]
            key("ESCAPE")
            assert "BLACK EMPEROR" in texts(observe())
            key("F1")
            manual = texts(observe())
            assert "FLIGHT MANUAL / 操作指南" in manual and "AIR SPEED" not in manual
            key("ESCAPE")
            assert "AIR SPEED" in texts(observe())
            snapshot = observe()
            button = next(n for n in walk(snapshot["ui"]) if n.get("text") == "开始试飞  Enter")
            x, y, width, height = button["rect"]
            advance(5, {"tap": {"x": int(x + width / 2), "y": int(y + height / 2)}})
            snapshot = observe()
            assert "BLACK EMPEROR" not in texts(snapshot), "Start button did not start the flight"
            assert aircraft(snapshot)["pos"][2] > -90, "Aircraft did not move forward"
            camera_button = next(n for n in walk(snapshot["ui"]) if n.get("text") == "C  /  追尾视角")
            x, y, width, height = camera_button["rect"]
            advance(4, {"tap": {"x": int(x + width / 2), "y": int(y + height / 2)}})
            snapshot = observe()
            assert not aircraft(snapshot)["enabled"] and cockpit(snapshot)["enabled"], "Cockpit must replace the airframe"
            assert "AIR SPEED" not in texts(snapshot), "Overlay must not cover the physical instruments"
            key("P")
            assert cockpit(observe())["enabled"], "Hiding HUD must not hide physical instruments"
            key("ESCAPE")
            key("C")
            snapshot = observe()
            assert aircraft(snapshot)["enabled"] and not cockpit(snapshot)["enabled"], "Side view must restore the airframe"
            assert "AIR SPEED" in texts(snapshot)
            advance(24, {"keys_down": ["LSHIFT"]})
            advance(3, {"keys_up": ["LSHIFT"]})
            assert "100%" in texts(observe()), "Throttle did not reach its upper limit"
            key("R")
            assert any("CROSSWIND 02" in t for t in texts(observe()))
            advance(460)
            snapshot = observe()
            assert "航线完成" in texts(snapshot) and "03 / 06" in texts(snapshot)
            assert "TRIAL COMPLETE" in texts(snapshot), "Completed trials must not show a nonexistent next gate"
            assert not cockpit(snapshot)["enabled"]
            key("RETURN")
            assert any("CROSSWIND 03" in t for t in texts(observe()))
            key("C")
            warning_seen = False
            for step in range(110):
                advance(inputs={"keys_down": ["S"]} if step == 0 else None)
                if not warning_seen:
                    warning_seen = "低空警告 / PULL UP" in texts(observe())
            assert warning_seen, "Low-altitude warning must appear before impact, including in the cockpit"
            advance(3, {"keys_up": ["S"]})
            snapshot = observe()
            assert "试飞中止" in texts(snapshot), "Diving into the sea must terminate the trial"
            assert not cockpit(snapshot)["enabled"] and aircraft(snapshot)["enabled"], "Crash must leave the cockpit view"
            report = call({"cmd": "finish"})
            (output / "interactive-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
            assert report["summary"]["lua_errors"] == 0 and not report["missing_resources"], report
            process.wait(timeout=10)
            assert process.returncode == 0
            print("PASS: start-button click, gear, photo/manual/escape, cameras, throttle, wind cycling, completion, sea impact")
        finally:
            if process.poll() is None:
                process.stdin.close()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
