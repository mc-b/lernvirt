#!/usr/bin/env python3
import argparse
import json
import math
from pathlib import Path
from typing import Dict, List

import torch
import yaml
from datasets import load_from_disk
from transformers import AutoModelForCausalLM, AutoTokenizer


DEFAULT_PROMPTS = [
    "Was wird im Modul CNA Unterrichtet",
    "Was wird im Modul IACA Unterrichtet",
    "Was verwende ich um ein Windows Image zu erstellen",
    "Wie installiere ich istio",
]


def load_config(path: str) -> Dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_prompts(path: str | None) -> List[str]:
    if not path:
        return DEFAULT_PROMPTS
    with open(path, "r", encoding="utf-8") as f:
        prompts = [line.strip() for line in f if line.strip()]
    return prompts or DEFAULT_PROMPTS


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate a continued-pretrained model.")
    parser.add_argument("--config", required=True, help="Path to YAML config")
    parser.add_argument("--model-path", required=True, help="Path or HF repo of the model to evaluate")
    parser.add_argument("--prompts-file", default=None, help="Optional text file with one prompt per line")
    args = parser.parse_args()

    cfg = load_config(args.config)
    gen_cfg = cfg.get("generation", {})
    train_cfg = cfg.get("training", {})

    tokenizer = AutoTokenizer.from_pretrained(args.model_path, use_fast=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    model = AutoModelForCausalLM.from_pretrained(args.model_path, torch_dtype="auto")
    model.eval()

    if torch.cuda.is_available():
        model = model.to("cuda")
    elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        model = model.to("mps")

    prompts = load_prompts(args.prompts_file)
    generations = []

    for prompt in prompts:
        inputs = tokenizer(prompt, return_tensors="pt")
        inputs = {k: v.to(model.device) for k, v in inputs.items()}
        with torch.no_grad():
            output = model.generate(
                **inputs,
                max_new_tokens=int(gen_cfg.get("max_new_tokens", 160)),
                temperature=float(gen_cfg.get("temperature", 0.8)),
                top_p=float(gen_cfg.get("top_p", 0.95)),
                do_sample=bool(gen_cfg.get("do_sample", True)),
                pad_token_id=tokenizer.pad_token_id,
                eos_token_id=tokenizer.eos_token_id,
            )
        text = tokenizer.decode(output[0], skip_special_tokens=True)
        generations.append({"prompt": prompt, "completion": text})

    # Approximate perplexity on local validation split if available
    ppl = None
    dataset_dir = Path(cfg["paths"]["dataset_dir"]).expanduser().resolve()
    if dataset_dir.exists():
        raw_ds = load_from_disk(str(dataset_dir))
        val_ratio = float(cfg["dataset"].get("val_ratio", 0.01))
        if val_ratio > 0.0 and len(raw_ds) > 0:
            split = raw_ds.train_test_split(test_size=val_ratio, seed=int(cfg["dataset"].get("seed", 42)))
            eval_ds = split["test"]
            block_size = int(train_cfg.get("block_size", 1024))
            losses = []
            limit = min(64, len(eval_ds))
            for i in range(limit):
                text = eval_ds[i]["text"]
                ids = tokenizer(text, return_tensors="pt", truncation=True, max_length=block_size)
                ids = {k: v.to(model.device) for k, v in ids.items()}
                with torch.no_grad():
                    out = model(**ids, labels=ids["input_ids"])
                losses.append(float(out.loss.detach().cpu().item()))
            if losses:
                ppl = math.exp(sum(losses) / len(losses))

    result = {
        "model_path": args.model_path,
        "perplexity_estimate": ppl,
        "generations": generations,
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
