from __future__ import annotations

import json
import os
from typing import Any, Dict, Optional

import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

DAPR_HTTP_PORT = os.getenv("DAPR_HTTP_PORT", "3500")
DAPR_BASE = f"http://127.0.0.1:{DAPR_HTTP_PORT}"
CONVERSATION_COMPONENT = os.getenv("CONVERSATION_COMPONENT", "llm-provider")

app = FastAPI(title="autoshop-diagnosis-agent", version="0.1.0")


class AnalyzeCaseRequest(BaseModel):
    case_id: str
    vehicle: Optional[str] = None
    customer_text: str = Field(..., min_length=10)


def converse(prompt: str) -> str:
    url = f"{DAPR_BASE}/v1.0-alpha2/conversation/{CONVERSATION_COMPONENT}/converse"
    body = {
        "inputs": [
            {
                "messages": [
                    {
                        "ofSystem": {
                            "content": [
                                {
                                    "text": (
                                        "Du bist ein Diagnose-Agent für eine Schweizer Autowerkstatt. "
                                        "Gib ausschliesslich valides JSON zurück mit den Feldern "
                                        "area, urgency, top_diagnosis, confidence, alternatives, "
                                        "recommended_check, safety_relevant."
                                    )
                                }
                            ]
                        }
                    },
                    {"ofUser": {"content": [{"text": prompt}]}}
                ]
            }
        ],
        "temperature": 0.2,
        "metadata": {},
        "parameters": {},
    }
    response = requests.post(url, json=body, timeout=90)
    response.raise_for_status()
    data = response.json()
    return data["outputs"][0]["choices"][0]["message"]["content"]


@app.get("/healthz")
def healthz() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/analyze-case")
def analyze_case(req: AnalyzeCaseRequest) -> Dict[str, Any]:
    prompt = (
        f"Fahrzeug: {req.vehicle or 'unbekannt'}
"
        f"Kundenbeschreibung: {req.customer_text}

"
        "Antworte nur mit JSON, Beispiel:
"
        '{"area":"bremsanlage","urgency":"hoch","top_diagnosis":"Bremsbeläge vorne abgenutzt","confidence":0.78,"alternatives":[{"cause":"Bremsscheiben verschlissen","confidence":0.61}],"recommended_check":"Bremsanlage vorne links prüfen","safety_relevant":true}'
    )
    try:
        raw = converse(prompt)
        parsed = json.loads(raw)
        parsed["agent"] = "diagnosis-agent"
        return parsed
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Diagnosis agent failed: {exc}") from exc


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8082)
