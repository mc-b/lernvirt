#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Dict, Optional

import yaml
from datasets import DatasetDict, load_from_disk
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    DataCollatorForLanguageModeling,
    Trainer,
    TrainingArguments,
)


def load_config(path: str) -> Dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def resolve_resume_path(resume_arg: Optional[str], output_dir: Path) -> Optional[str]:
    if not resume_arg:
        return None
    if resume_arg != "auto":
        return resume_arg

    checkpoints = sorted(output_dir.glob("checkpoint-*"), key=lambda p: p.stat().st_mtime)
    if not checkpoints:
        return None
    return str(checkpoints[-1])


def build_splits(cfg: Dict):
    dataset_dir = Path(cfg["paths"]["dataset_dir"]).expanduser().resolve()
    raw_ds = load_from_disk(str(dataset_dir))

    val_ratio = float(cfg["dataset"].get("val_ratio", 0.01))
    seed = int(cfg["dataset"].get("seed", 42))

    if val_ratio > 0.0:
        split_ds = raw_ds.train_test_split(test_size=val_ratio, seed=seed)
        return DatasetDict({"train": split_ds["train"], "validation": split_ds["test"]})
    return DatasetDict({"train": raw_ds})


def main() -> None:
    parser = argparse.ArgumentParser(description="Continued pretraining on local Wikipedia dataset.")
    parser.add_argument("--config", required=True, help="Path to YAML config")
    parser.add_argument("--resume", default=None, help="Checkpoint path or 'auto'")
    args = parser.parse_args()

    cfg = load_config(args.config)
    paths_cfg = cfg["paths"]
    model_cfg = cfg["model"]
    train_cfg = cfg["training"]
    lora_cfg = cfg.get("lora", {})

    output_dir = Path(paths_cfg["output_dir"]).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    ds = build_splits(cfg)

    tokenizer = AutoTokenizer.from_pretrained(
        model_cfg["name"],
        use_fast=model_cfg.get("use_fast_tokenizer", True),
        trust_remote_code=model_cfg.get("trust_remote_code", False),
        cache_dir=paths_cfg.get("cache_dir"),
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    def tokenize_fn(batch):
        return tokenizer(batch["text"])

    tokenized = ds.map(
        tokenize_fn,
        batched=True,
        remove_columns=ds["train"].column_names,
        desc="Tokenizing dataset",
    )

    block_size = int(train_cfg.get("block_size", 1024))

    def group_texts(examples):
        concatenated = {k: sum(examples[k], []) for k in examples.keys()}
        total_length = len(concatenated["input_ids"])
        total_length = (total_length // block_size) * block_size
        result = {
            k: [v[i:i + block_size] for i in range(0, total_length, block_size)]
            for k, v in concatenated.items()
        }
        result["labels"] = result["input_ids"].copy()
        return result

    lm_ds = tokenized.map(group_texts, batched=True, desc=f"Grouping into blocks of {block_size}")

    if train_cfg.get("max_eval_samples_blocks") and "validation" in lm_ds:
        max_eval = int(train_cfg["max_eval_samples_blocks"])
        if len(lm_ds["validation"]) > max_eval:
            lm_ds["validation"] = lm_ds["validation"].select(range(max_eval))

    model = AutoModelForCausalLM.from_pretrained(
        model_cfg["name"],
        trust_remote_code=model_cfg.get("trust_remote_code", False),
        torch_dtype="auto",
        cache_dir=paths_cfg.get("cache_dir"),
    )

    if train_cfg.get("gradient_checkpointing", True):
        model.gradient_checkpointing_enable()
        if hasattr(model, "config"):
            model.config.use_cache = False

    if lora_cfg.get("enabled", False):
        from peft import LoraConfig, TaskType, get_peft_model

        peft_config = LoraConfig(
            task_type=TaskType.CAUSAL_LM,
            r=int(lora_cfg.get("r", 16)),
            lora_alpha=int(lora_cfg.get("alpha", 32)),
            lora_dropout=float(lora_cfg.get("dropout", 0.05)),
            target_modules=lora_cfg.get("target_modules", None),
        )
        model = get_peft_model(model, peft_config)
        model.print_trainable_parameters()

    data_collator = DataCollatorForLanguageModeling(tokenizer=tokenizer, mlm=False)

    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=float(train_cfg.get("num_train_epochs", 1)),
        learning_rate=float(train_cfg.get("learning_rate", 2e-5)),
        weight_decay=float(train_cfg.get("weight_decay", 0.01)),
        warmup_ratio=float(train_cfg.get("warmup_ratio", 0.03)),
        per_device_train_batch_size=int(train_cfg.get("per_device_train_batch_size", 1)),
        per_device_eval_batch_size=int(train_cfg.get("per_device_eval_batch_size", 1)),
        gradient_accumulation_steps=int(train_cfg.get("gradient_accumulation_steps", 16)),
        logging_steps=int(train_cfg.get("logging_steps", 10)),
        eval_steps=int(train_cfg.get("eval_steps", 250)),
        save_steps=int(train_cfg.get("save_steps", 250)),
        save_total_limit=int(train_cfg.get("save_total_limit", 2)),
        dataloader_num_workers=int(train_cfg.get("dataloader_num_workers", 2)),
        bf16=bool(train_cfg.get("bf16", True)),
        fp16=bool(train_cfg.get("fp16", False)),
        gradient_checkpointing=bool(train_cfg.get("gradient_checkpointing", True)),
        max_grad_norm=float(train_cfg.get("max_grad_norm", 1.0)),
        lr_scheduler_type=train_cfg.get("lr_scheduler_type", "cosine"),
        report_to=train_cfg.get("report_to", "none"),
        eval_strategy="steps" if train_cfg.get("do_eval", True) and "validation" in lm_ds else "no",
        save_strategy="steps",
        logging_strategy="steps",
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=lm_ds["train"],
        eval_dataset=lm_ds.get("validation"),
        processing_class=tokenizer,
        data_collator=data_collator,
    )

    resume_path = resolve_resume_path(args.resume, output_dir)
    train_result = trainer.train(resume_from_checkpoint=resume_path)

    trainer.save_model(str(output_dir / "final"))
    tokenizer.save_pretrained(str(output_dir / "final"))

    metrics = train_result.metrics
    if train_cfg.get("do_eval", True) and "validation" in lm_ds:
        eval_metrics = trainer.evaluate()
        metrics.update({f"final_{k}": v for k, v in eval_metrics.items()})

    with open(output_dir / "metrics.json", "w", encoding="utf-8") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=2)

    print(json.dumps(metrics, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
