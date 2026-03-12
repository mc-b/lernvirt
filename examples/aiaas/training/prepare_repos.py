#!/usr/bin/env python3

import argparse
import json
import re
from pathlib import Path

import yaml
from datasets import Dataset


SKIP_DIRS = {
    ".git",
    "node_modules",
    "target",
    "dist",
    "build",
    "__pycache__",
    ".idea",
    ".vscode",
}


TEXT_SUFFIXES = {
    ".md",
    ".txt",
    ".rst",
    ".py",
    ".java",
    ".js",
    ".ts",
    ".tsx",
    ".jsx",
    ".json",
    ".yaml",
    ".yml",
    ".xml",
    ".html",
    ".css",
    ".sh",
    ".sql",
    ".c",
    ".cpp",
    ".h",
    ".hpp",
    ".go",
    ".rs",
    ".kt",
    ".scala",
    ".properties",
    ".gradle",
    ".cfg",
    ".conf",
    ".ini",
}


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def chunk_text(text: str, max_chars: int, overlap: int):
    chunks = []
    start = 0

    while start < len(text):
        end = min(start + max_chars, len(text))
        chunk = text[start:end].strip()

        if chunk:
            chunks.append(chunk)

        if end >= len(text):
            break

        start = max(0, end - overlap)

    return chunks


def extract_java_comments(text: str) -> str:
    blocks = re.findall(r"/\*\*(.*?)\*/", text, flags=re.DOTALL)
    blocks += re.findall(r"/\*(.*?)\*/", text, flags=re.DOTALL)
    lines = re.findall(r"(?m)^\s*//(.*)$", text)

    comments = blocks + lines
    cleaned = []

    for c in comments:
        c = re.sub(r"(?m)^\s*\*\s?", "", c)
        c = normalize_text(c)
        if c:
            cleaned.append(c)

    return "\n\n".join(cleaned)


def extract_ipynb(path: Path) -> str:
    import nbformat

    with path.open("r", encoding="utf-8") as f:
        nb = nbformat.read(f, as_version=4)

    parts = []

    for cell in nb.cells:
        if cell.cell_type == "markdown":
            parts.append(cell.source)

    return "\n\n".join(parts)


def is_probably_text_file(path: Path) -> bool:
    if path.suffix.lower() in TEXT_SUFFIXES:
        return True

    try:
        with path.open("rb") as f:
            sample = f.read(4096)

        if b"\x00" in sample:
            return False

        sample.decode("utf-8")
        return True

    except Exception:
        return False


def find_git_repos(root: Path):
    seen = set()

    if (root / ".git").exists():
        repo = root.resolve()
        seen.add(repo)
        yield repo

    for p in root.rglob(".git"):
        repo = p.parent.resolve()
        if repo not in seen:
            seen.add(repo)
            yield repo


def iter_files(repo: Path):
    for p in repo.rglob("*"):
        if not p.is_file():
            continue

        if any(part in SKIP_DIRS for part in p.parts):
            continue

        yield p


def build_records(repo: Path, path: Path, mode: str, cfg: dict):
    suffix = path.suffix.lower()
    text = None
    kind = None

    try:
        if suffix in {".md", ".txt", ".rst"}:
            text = path.read_text(encoding="utf-8", errors="ignore")
            kind = "docs"

        elif suffix == ".java":
            raw = path.read_text(encoding="utf-8", errors="ignore")

            if mode == "docs":
                text = extract_java_comments(raw)
                kind = "java_comments"

            elif mode == "docs+comments":
                text = extract_java_comments(raw)
                kind = "java_comments"

            else:
                text = raw
                kind = "java_full"

        elif suffix == ".ipynb":
            text = extract_ipynb(path)
            kind = "notebook"

        elif mode == "full":
            if not is_probably_text_file(path):
                return []

            text = path.read_text(encoding="utf-8", errors="ignore")
            kind = "text_full"

    except Exception as e:
        print(f"warning: could not read {path}: {e}")
        return []

    if not text:
        return []

    text = normalize_text(text)

    if len(text) < cfg["min_chars"]:
        return []

    chunks = chunk_text(text, cfg["max_chars"], cfg["overlap"])
    records = []

    for i, chunk in enumerate(chunks):
        if len(chunk) < cfg["min_chars"]:
            continue

        records.append(
            {
                "text": chunk,
                "repo": repo.name,
                "path": str(path.relative_to(repo)),
                "kind": kind,
                "chunk_id": i,
            }
        )

    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, help="Pfad zur config.yaml")
    args = parser.parse_args()

    config_path = Path(args.config)

    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with config_path.open("r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    if cfg is None:
        raise ValueError(f"Config file is empty: {config_path}")

    # erlaubt beide Formate:
    # repos: {...}
    # oder direkt {...}
    repo_cfg = cfg.get("repos", cfg)

    required = [
        "root_dir",
        "output_dir",
        "mode",
        "max_chars",
        "overlap",
        "min_chars",
    ]

    missing = [k for k in required if k not in repo_cfg]
    if missing:
        raise KeyError(f"Missing required config keys: {missing}")

    root = Path(repo_cfg["root_dir"]).expanduser().resolve()

    if not root.exists():
        raise FileNotFoundError(f"root_dir does not exist: {root}")

    print("configured root:", root)

    # einfacher: root direkt als repo verwenden
    repos = [root]

    print("repos found:", len(repos))

    records = []

    for repo in repos:
        print("scanning repo:", repo)

        for path in iter_files(repo):
            recs = build_records(repo, path, repo_cfg["mode"], repo_cfg)
            records.extend(recs)

    print("records collected:", len(records))

    if not records:
        print("warning: no records collected")

    ds = Dataset.from_list(records)

    output_dir = Path(repo_cfg["output_dir"]).expanduser().resolve()
    output_dir.parent.mkdir(parents=True, exist_ok=True)

    ds.save_to_disk(str(output_dir))

    print(
        json.dumps(
            {
                "records": len(ds),
                "repos": len(repos),
                "output_dir": str(output_dir),
            },
            indent=2,
        )
    )

if __name__ == "__main__":
    main()
    
    
    
    
    