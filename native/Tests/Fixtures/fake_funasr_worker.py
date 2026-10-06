#!/usr/bin/env python3
import json
import sys
import time

for line in sys.stdin:
    request = json.loads(line)
    command = request.get("command")
    if command == "hang":
        time.sleep(5)
        continue
    if command == "shutdown":
        print(json.dumps({"id": request["id"], "ok": True, "shutdown": True}), flush=True)
        break
    if command == "warmup":
        print(json.dumps({"id": request["id"], "ok": True, "engine": f"{request['provider']}/fake"}), flush=True)
        continue
    if command == "transcribe":
        print(json.dumps({
            "id": request["id"],
            "ok": True,
            "text": "测试识别",
            "engine": f"{request['provider']}/fake",
            "duration_sec": 0.01,
            "hotword_strategy": request.get("hotword_strategy"),
            "hotword_count": len(request.get("hotwords", [])),
        }), flush=True)
        continue
    print(json.dumps({"id": request["id"], "ok": True, "ready": True}), flush=True)
