from __future__ import annotations

import threading
from typing import Any, Dict

import dapr.ext.workflow as wf
from fastapi import FastAPI
from pydantic import BaseModel

from common import invoke_service, merge_case

STATESTORE = "statestore"

app = FastAPI(title="autoshop-orchestrator", version="0.1.0")
wfr = wf.WorkflowRuntime()
_runtime_lock = threading.Lock()
_runtime_started = False


class StartCaseRequest(BaseModel):
    case_id: str
    vehicle: str | None = None
    customer_text: str


def ensure_runtime() -> None:
    global _runtime_started
    with _runtime_lock:
        if not _runtime_started:
            wfr.start()
            _runtime_started = True


@wfr.activity(name="mark_started")
def mark_started(ctx, payload: Dict[str, Any]) -> Dict[str, Any]:
    return merge_case(STATESTORE, payload["case_id"], {"status": "started"})


@wfr.activity(name="call_diagnosis_agent")
def call_diagnosis_agent(ctx, payload: Dict[str, Any]) -> Dict[str, Any]:
    result = invoke_service("diagnosis-agent", "analyze-case", payload, timeout=90)
    merge_case(STATESTORE, payload["case_id"], {"status": "diagnosed", "diagnosis": result})
    return result


@wfr.activity(name="call_parts_agent")
def call_parts_agent(ctx, payload: Dict[str, Any]) -> Dict[str, Any]:
    result = invoke_service("parts-agent", "build-quote", payload, timeout=30)
    merge_case(STATESTORE, payload["case_id"], {"status": "quoted", "quote": result})
    return result


@wfr.activity(name="call_offer_agent")
def call_offer_agent(ctx, payload: Dict[str, Any]) -> Dict[str, Any]:
    result = invoke_service("offer-agent", "compose-offer", payload, timeout=90)
    merge_case(STATESTORE, payload["case_id"], {"status": "completed", "offer": result})
    return result


@wfr.workflow(name="garage_quote_workflow")
def garage_quote_workflow(ctx: wf.DaprWorkflowContext, wf_input: Dict[str, Any]):
    yield ctx.call_activity(mark_started, input=wf_input)
    diagnosis = yield ctx.call_activity(call_diagnosis_agent, input=wf_input)
    quote = yield ctx.call_activity(
        call_parts_agent,
        input={
            "case_id": wf_input["case_id"],
            "vehicle": wf_input.get("vehicle"),
            "customer_text": wf_input["customer_text"],
            "diagnosis": diagnosis,
        },
    )
    offer = yield ctx.call_activity(
        call_offer_agent,
        input={
            "case_id": wf_input["case_id"],
            "vehicle": wf_input.get("vehicle"),
            "customer_text": wf_input["customer_text"],
            "diagnosis": diagnosis,
            "quote": quote,
        },
    )
    return {"case_id": wf_input["case_id"], "diagnosis": diagnosis, "quote": quote, "offer": offer}


@app.on_event("startup")
def on_startup() -> None:
    ensure_runtime()


@app.get("/healthz")
def healthz() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/start-case")
def start_case(req: StartCaseRequest) -> Dict[str, str]:
    ensure_runtime()
    client = wf.DaprWorkflowClient()
    workflow_instance_id = client.schedule_new_workflow(workflow=garage_quote_workflow, input=req.model_dump())
    return {"workflow_instance_id": workflow_instance_id}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8081)
