from __future__ import annotations

import os
from typing import Any, Dict, Optional

import requests

DAPR_HTTP_PORT = os.getenv("DAPR_HTTP_PORT", "3500")
DAPR_BASE = f"http://127.0.0.1:{DAPR_HTTP_PORT}"


def invoke_service(app_id: str, method: str, payload: Dict[str, Any], timeout: int = 60) -> Dict[str, Any]:
    url = f"{DAPR_BASE}/v1.0/invoke/{app_id}/method/{method.lstrip('/')}"
    response = requests.post(url, json=payload, timeout=timeout)
    response.raise_for_status()
    return response.json()


def save_state(store_name: str, key: str, value: Dict[str, Any]) -> None:
    url = f"{DAPR_BASE}/v1.0/state/{store_name}"
    body = [{"key": key, "value": value}]
    response = requests.post(url, json=body, timeout=30)
    response.raise_for_status()


def get_state(store_name: str, key: str) -> Optional[Dict[str, Any]]:
    url = f"{DAPR_BASE}/v1.0/state/{store_name}/{key}"
    response = requests.get(url, timeout=30)
    if response.status_code in (204, 404):
        return None
    response.raise_for_status()
    try:
        return response.json()
    except Exception:
        return None


def merge_case(store_name: str, case_id: str, patch: Dict[str, Any]) -> Dict[str, Any]:
    key = f"case:{case_id}"
    current = get_state(store_name, key) or {}
    current.update(patch)
    save_state(store_name, key, current)
    return current
