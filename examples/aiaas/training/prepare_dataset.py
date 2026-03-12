#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Dict, Iterator

import yaml
from datasets import Dataset, load_dataset


def load_config(path: str) -> Dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def clean_text(text: str) -> str:
    text = text.replace("\xa0", " ")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return "\n".join(lines).strip()


def iter_articles(cfg: Dict) -> Iterator[Dict[str, str]]:
    ds_cfg = cfg["dataset"]
    ds = load_dataset(
        ds_cfg["hf_name"],
        ds_cfg["wikipedia_config"],
        split=ds_cfg.get("split", "train"),
        streaming=ds_cfg.get("streaming", True),
        cache_dir=cfg["paths"].get("cache_dir"),
    )

    text_column = ds_cfg.get("text_column", "text")
    min_chars = int(ds_cfg.get("min_chars", 500))
    max_articles = int(ds_cfg.get("max_articles", 50000))

    count = 0
    for row in ds:
        text = row.get(text_column, "")
        if not isinstance(text, str):
            continue
        text = clean_text(text)
        if len(text) < min_chars:
            continue

        yield {"text": text}
        count += 1
        if count >= max_articles:
            break


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare local Wikipedia dataset for continued pretraining.")
    parser.add_argument("--config", required=True, help="Path to YAML config")
    args = parser.parse_args()

    cfg = load_config(args.config)
    output_dir = Path(cfg["paths"]["dataset_dir"]).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    records = list(iter_articles(cfg))
    if not records:
        raise RuntimeError("No articles found after filtering. Check dataset config.")

    dataset = Dataset.from_list(records)
    dataset.save_to_disk(str(output_dir))

    manifest = {
        "num_articles": len(dataset),
        "dataset_dir": str(output_dir),
        "source": cfg["dataset"]["hf_name"],
        "wikipedia_config": cfg["dataset"]["wikipedia_config"],
        "min_chars": cfg["dataset"].get("min_chars", 500),
        "max_articles": cfg["dataset"].get("max_articles", 50000),
    }
    with open(output_dir / "manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
