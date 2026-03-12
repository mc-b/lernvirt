# Wikipedia Continued Pretraining für DGX Spark

Dieses Projekt baut ein kleines, reproduzierbares Setup für **Continued Pretraining** eines bestehenden Causal-LM-Base-Modells auf dem Hugging-Face-Dataset `wikimedia/wikipedia`.

Der Ablauf ist bewusst in zwei Phasen getrennt:

1. `prepare_dataset.py` lädt und bereinigt Wikipedia-Artikel und schreibt ein lokales Arrow-Dataset.
2. `train.py` tokenisiert dieses lokale Dataset, baut Token-Blöcke und trainiert das Modell weiter.
3. `eval.py` prüft das Resultat mit wenigen Textgenerierungen und optionaler Perplexity auf einem Holdout-Split.

## Zielbild

Dieses Projekt ist für **Continued Pretraining**, nicht für klassisches Chat-Finetuning. Verwende daher ein **Base-Modell** und kein Instruct-Modell, wenn du die Gewichte im Vortrainingsstil weiter verschieben willst.

Ein guter Start auf einer DGX Spark ist:

- Modell: `Qwen/Qwen2.5-1.5B`
- Wikipedia-Snapshot: `20231101.de`
- Block Size: `1024`
- `per_device_train_batch_size: 1`
- `gradient_accumulation_steps: 16`
- `bf16: true`

## Verzeichnisstruktur

```text
.
├── config.example.yaml
├── eval.py
├── generate.py
├── prepare_dataset.py
├── README.md
├── requirements.txt
└── train.py
```

## 1) Umgebung vorbereiten

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```

Falls `torch` auf deiner DGX Spark bereits über NVIDIA/PyTorch-Container oder System-Stack sauber vorhanden ist, kannst du `requirements.txt` bei Bedarf anpassen.

## 2) Konfiguration anlegen

```bash
cp config.example.yaml config.yaml
```

Danach in `config.yaml` die wichtigsten Werte prüfen:

- `model.name`
- `dataset.wikipedia_config`
- `paths.dataset_dir`
- `paths.output_dir`

## 3) Wikipedia lokal vorbereiten

```bash
python prepare_dataset.py --config config.yaml
```

Das Script:

- streamt `wikimedia/wikipedia`
- filtert kurze oder leere Artikel
- macht nur eine grobe Textbereinigung
- schreibt ein lokales Dataset nach `paths.dataset_dir`

## 4) Training starten

```bash
python train.py --config config.yaml
```

Wichtige Eigenschaften:

- lokales Dataset wird erneut geladen
- Tokenisierung mit dem Modell-Tokenizer
- Gruppierung in feste Token-Blöcke
- Holdout-Split für optionale Evaluation
- Checkpoints in `paths.output_dir`
- Resume ab letztem Checkpoint mit `--resume auto`

Explizites Resume:

```bash
python train.py --config config.yaml --resume auto
```

Oder ab bestimmtem Checkpoint:

```bash
python train.py --config config.yaml --resume ./outputs/wiki-cpt/checkpoint-1000
```

## 5) Evaluation

Schnelle Textausgabe vor/nach dem Training:

```bash
python generate.py \
  --model ./outputs/wiki-cpt/final \
  --prompt "Die Geschichte der Schweiz ist" \
  --max-new-tokens 160
```

Perplexity und Beispielgenerationen:

```bash
python eval.py --config config.yaml --model-path ./outputs/wiki-cpt/final
```

## Typische Anpassungen für DGX Spark

### Kleiner und sicherer Start

Für den ersten Lauf:

- `dataset.max_articles: 50000`
- `training.block_size: 1024`
- `training.per_device_train_batch_size: 1`
- `training.gradient_accumulation_steps: 16`
- `training.num_train_epochs: 1`

### Danach hochskalieren

Wenn der erste Lauf stabil ist:

- `dataset.max_articles` erhöhen
- `training.block_size` auf `2048` testen
- mehr Epochen oder mehr Artikel
- optional LoRA aktivieren

## LoRA optional

In `config.yaml` kann `lora.enabled: true` gesetzt werden. Das spart Speicher und reduziert die Anzahl trainierbarer Parameter. Für klassisches Continued Pretraining ist Full Fine-Tuning methodisch näher am Vortraining, aber LoRA ist auf begrenzter Hardware oft praktischer.

Für Qwen2.5 sind als Default-Targets im Beispiel gesetzt:

- `q_proj`
- `k_proj`
- `v_proj`
- `o_proj`
- `up_proj`
- `down_proj`
- `gate_proj`

Bei anderen Architekturen müssen diese Layernamen ggf. angepasst werden.

## Hinweise zur Lizenz

Wikipedia-Inhalte stehen nicht unter einer simplen Public-Domain-Lizenz. Prüfe die Bedingungen des verwendeten Datasets und der weiterverwendeten Modellartefakte separat, bevor du das Resultat extern verteilst oder kommerziell einsetzt.

## Beispielworkflow

```bash
cp config.example.yaml config.yaml
python prepare_dataset.py --config config.yaml
python train.py --config config.yaml
python eval.py --config config.yaml --model-path ./outputs/wiki-cpt/final
```

## Bekannte praktische Grenzen

- Das ist **kein** Full-Scale-Foundation-Pretraining ab Scratch.
- Wikipedia allein ergibt kein starkes Chatmodell.
- Nach Continued Pretraining ist oft ein nachgelagertes Instruction-Tuning sinnvoll.
- Perplexity auf Wikipedia ist nützlich, aber nicht hinreichend als Qualitätsmass.

## Nächste sinnvolle Ausbaustufen

- dedizierter deutscher Holdout-Split
- W&B / MLflow Logging
- Mixed-precision-Tuning und Grad-Checkpointing-Profile
- mehrere Shards statt eines einzelnen vorbereiteten Datasets
- nachgelagertes deutschsprachiges Instruction-Tuning
