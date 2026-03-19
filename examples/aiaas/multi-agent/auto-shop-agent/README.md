# Dapr Auto Shop – echtes Minimal-Referenzprojekt

Dieses Beispiel zeigt bewusst **Dapr-Fähigkeiten statt direkter Provider-SDKs**:

- **Conversation API** für LLM-Zugriff in `diagnosis-agent` und `offer-agent`
- **Service Invocation** zwischen `intake-api`, `orchestrator`, `diagnosis-agent`, `parts-agent`, `offer-agent`
- **Workflow** im `orchestrator` für langlebige Orchestrierung
- **State Store** für den Fallstatus (`case:{id}`) in Redis

## Architektur

```text
Client
  |
  v
intake-api
  |  (Dapr service invocation)
  v
orchestrator  --workflow--> diagnosis-agent  --Conversation API--> llm-provider
     |                             |
     |                             +--> strukturiertes Diagnose-JSON
     |
     +--> parts-agent        (klassischer Microservice)
     |
     +--> offer-agent        --Conversation API--> llm-provider
     |
     +--> schreibt Status/Resultate in statestore
```

## Services

- `intake-api`: öffentliche API für `POST /cases` und `GET /cases/{id}`
- `orchestrator`: Dapr Workflow Worker + Start-Endpunkt
- `diagnosis-agent`: LLM-basierte Erstdiagnose über Dapr Conversation API
- `parts-agent`: deterministische Teile-/Preislogik
- `offer-agent`: LLM-basierte Angebotsformulierung über Dapr Conversation API

## Voraussetzungen

- Kubernetes oder k3s
- Dapr auf dem Cluster
- Container Registry, die der Cluster ziehen kann
- OpenAI oder OpenAI-kompatibler Endpoint

## Wichtige Dapr-Rolle

Der Code spricht **nicht direkt** gegen das OpenAI-SDK.
Die Agenten sprechen gegen den lokalen Dapr-Sidecar:

- `POST /v1.0-alpha2/conversation/llm-provider/converse`
- `POST /v1.0/invoke/<appId>/method/<method>`

Das LLM wird über die Dapr-Komponente `llm-provider` konfiguriert.

## Build

Passe in `k8s/apps.yaml` die Image-Namen an und baue dann alle Images:

```bash
docker build -t YOUR_REGISTRY/autoshop-intake:0.1.0 services/intake-api
docker build -t YOUR_REGISTRY/autoshop-orchestrator:0.1.0 services/orchestrator
docker build -t YOUR_REGISTRY/autoshop-diagnosis:0.1.0 services/diagnosis-agent
docker build -t YOUR_REGISTRY/autoshop-parts:0.1.0 services/parts-agent
docker build -t YOUR_REGISTRY/autoshop-offer:0.1.0 services/offer-agent

docker push YOUR_REGISTRY/autoshop-intake:0.1.0
docker push YOUR_REGISTRY/autoshop-orchestrator:0.1.0
docker push YOUR_REGISTRY/autoshop-diagnosis:0.1.0
docker push YOUR_REGISTRY/autoshop-parts:0.1.0
docker push YOUR_REGISTRY/autoshop-offer:0.1.0
```

## Deploy

1. Dapr installieren:

```bash
dapr init -k
```

2. Namespace, Redis und Dapr-Komponenten deployen:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/components/
kubectl apply -f k8s/apps.yaml
```

## LLM konfigurieren

In `k8s/secret.yaml` und `k8s/components/llm-provider.yaml`:

- `llm-api-key`
- `endpoint`
- `model`

Beispiel für OpenAI-kompatiblen lokalen Endpoint:

```yaml
- name: endpoint
  value: "http://sglang-service.default.svc.cluster.local:30000/v1"
```

## Test

```bash
kubectl -n autoshop port-forward svc/intake-api 8080:8080
```

Neuen Fall anlegen:

```bash
curl -X POST http://127.0.0.1:8080/cases   -H "Content-Type: application/json"   -d '{
    "vehicle": "VW Golf 7",
    "customer_text": "Beim Bremsen vorne links schleift es metallisch."
  }'
```

Fallstatus abfragen:

```bash
curl http://127.0.0.1:8080/cases/CASE_ID
```

## Erwartetes Resultat

Der Status im State Store läuft typischerweise durch:

- `received`
- `workflow_scheduled`
- `diagnosed`
- `quoted`
- `completed`

## Bewusste Grenzen des Beispiels

Dieses Projekt ist absichtlich minimal:

- keine echte Lagerdatenbank
- keine echte Terminbuchung
- keine Tool-Calling-Schleife in der Conversation API
- keine Pub/Sub-Events

Es zeigt aber die zentralen Dapr-Muster sauber:
**Conversation API + Service Invocation + Workflow + State Store**.
