from __future__ import annotations

import uuid
from typing import Any, Dict, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from common import get_state, invoke_service, save_state

STATESTORE = "statestore"

app = FastAPI(title="autoshop-intake-api", version="0.1.0")


class CreateCaseRequest(BaseModel):
    vehicle: Optional[str] = None
    customer_text: str = Field(..., min_length=10)


@app.get("/healthz")
def healthz() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/cases")
def create_case(req: CreateCaseRequest) -> Dict[str, Any]:
    case_id = str(uuid.uuid4())
    state = {
        "case_id": case_id,
        "vehicle": req.vehicle,
        "customer_text": req.customer_text,
        "status": "received",
    }
    save_state(STATESTORE, f"case:{case_id}", state)

    orchestrator_resp = invoke_service(
        "orchestrator",
        "start-case",
        {
            "case_id": case_id,
            "vehicle": req.vehicle,
            "customer_text": req.customer_text,
        },
    )

    state["status"] = "workflow_scheduled"
    state["workflow_instance_id"] = orchestrator_resp["workflow_instance_id"]
    save_state(STATESTORE, f"case:{case_id}", state)

    return {
        "case_id": case_id,
        "workflow_instance_id": orchestrator_resp["workflow_instance_id"],
        "status": state["status"],
    }


@app.get("/cases/{case_id}")
def get_case(case_id: str) -> Dict[str, Any]:
    result = get_state(STATESTORE, f"case:{case_id}")
    if result is None:
        raise HTTPException(status_code=404, detail="Case not found")
    return result


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8080)
