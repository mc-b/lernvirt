from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="autoshop-parts-agent", version="0.1.0")


class BuildQuoteRequest(BaseModel):
    case_id: str
    vehicle: Optional[str] = None
    customer_text: str
    diagnosis: Dict[str, Any]


def quote_for_diagnosis(top_diagnosis: str) -> Dict[str, Any]:
    t = top_diagnosis.lower()
    if "bremsbeläge" in t:
        parts = [{"name": "Bremsbelagsatz vorne", "price_chf": 120.0}, {"name": "Kleinmaterial", "price_chf": 18.0}]
        labor_hours = 1.2
    elif "bremsscheiben" in t:
        parts = [{"name": "Bremsscheiben vorne", "price_chf": 220.0}, {"name": "Bremsbelagsatz vorne", "price_chf": 120.0}, {"name": "Kleinmaterial", "price_chf": 18.0}]
        labor_hours = 1.8
    else:
        parts = []
        labor_hours = 0.8
    labor_rate = 145.0
    parts_total = round(sum(p["price_chf"] for p in parts), 2)
    labor_total = round(labor_hours * labor_rate, 2)
    base_total = parts_total + labor_total
    return {
        "agent": "parts-agent",
        "parts": parts,
        "labor_hours": labor_hours,
        "labor_rate_chf": labor_rate,
        "parts_total_chf": parts_total,
        "labor_total_chf": labor_total,
        "estimated_min_chf": round(base_total * 0.9, 2),
        "estimated_max_chf": round(base_total * 1.2, 2),
    }


@app.get("/healthz")
def healthz() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/build-quote")
def build_quote(req: BuildQuoteRequest) -> Dict[str, Any]:
    top_diagnosis = req.diagnosis.get("top_diagnosis", "Allgemeine technische Prüfung")
    quote = quote_for_diagnosis(top_diagnosis)
    quote["top_diagnosis"] = top_diagnosis
    return quote


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8083)
