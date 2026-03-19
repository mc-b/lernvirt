from __future__ import annotations

import json
import os
from typing import Any, Dict, Optional

import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DAPR_HTTP_PORT = os.getenv("DAPR_HTTP_PORT", "3500")
DAPR_BASE = f"http://127.0.0.1:{DAPR_HTTP_PORT}"
CONVERSATION_COMPONENT = os.getenv("CONVERSATION_COMPONENT", "llm-provider")

app = FastAPI(title="autoshop-offer-agent", version="0.1.0")


class ComposeOfferRequest(BaseModel):
    case_id: str
    vehicle: Optional[str] = None
    customer_text: str
    diagnosis: Dict[str, Any]
    quote: Dict[str, Any]


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
                                        "Du bist ein Angebots-Agent für eine Schweizer Autowerkstatt. "
                                        "Gib ausschliesslich valides JSON zurück mit den Feldern "
                                        "summary, recommended_action, customer_message."
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


@app.post("/compose-offer")
def compose_offer(req: ComposeOfferRequest) -> Dict[str, Any]:
    prompt = (
        f"Fahrzeug: {req.vehicle or 'unbekannt'}
"
        f"Kundenbeschreibung: {req.customer_text}
"
        f"Diagnose: {json.dumps(req.diagnosis, ensure_ascii=False)}
"
        f"Quote: {json.dumps(req.quote, ensure_ascii=False)}

"
        "Erzeuge nur JSON, Beispiel:
"
        '{"summary":"Wahrscheinlich sind die Bremsbeläge vorne abgenutzt.","recommended_action":"Bremsanlage zeitnah prüfen und Beläge ersetzen.","customer_message":"Vorläufige Kostenschätzung CHF 280 bis CHF 380. Diese Einschätzung ersetzt keine Werkstattdiagnose."}'
    )
    try:
        raw = converse(prompt)
        parsed = json.loads(raw)
        parsed["agent"] = "offer-agent"
        parsed["estimated_min_chf"] = req.quote.get("estimated_min_chf")
        parsed["estimated_max_chf"] = req.quote.get("estimated_max_chf")
        return parsed
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Offer agent failed: {exc}") from exc


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8084)
