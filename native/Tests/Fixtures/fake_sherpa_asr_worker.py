#!/usr/bin/env python3
import json
import sys

loaded = None
for line in sys.stdin:
    request = json.loads(line)
    command = request["command"]
    provider = request.get("provider")
    if command == "warmup":
        loaded = provider
        print(json.dumps({"id": request["id"], "ok": True, "ready": True,
                          "engine": provider + "/fake", "load_sec": 0.01}), flush=True)
    elif command == "transcribe":
        if provider == "crash-255":
            sys.exit(255)
        ok = loaded == provider
        print(json.dumps({"id": request["id"], "ok": ok,
                          "text": "Sherpa 隔离测试" if ok else None,
                          "engine": provider + "/fake" if ok else None,
                          "duration_sec": 0.02,
                          "error": None if ok else "not warmed"}), flush=True)
    elif command == "shutdown":
        print(json.dumps({"id": request["id"], "ok": True, "shutdown": True}), flush=True)
        break
