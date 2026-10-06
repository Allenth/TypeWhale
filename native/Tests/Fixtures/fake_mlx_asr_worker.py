#!/usr/bin/env python3
import json, sys
for line in sys.stdin:
    request=json.loads(line); command=request.get("command"); response={"id":request["id"],"ok":True}
    if command=="warmup": response.update(engine=f'{request["provider"]}/fake',load_sec=0.01)
    elif command=="transcribe": response.update(text="MLX 测试识别",engine=f'{request["provider"]}/fake',duration_sec=0.02,hotword_strategy="context_prompt")
    elif command=="health": response["ready"]=True
    elif command=="shutdown": response["shutdown"]=True
    print(json.dumps(response,ensure_ascii=False),flush=True)
    if response.get("shutdown"): break
