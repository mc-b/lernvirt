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


def normalize_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def chunk_text(text, max_chars, overlap):
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


def extract_java_comments(text):
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


def extract_ipynb(path):
    import nbformat

    with path.open() as f:
        nb = nbformat.read(f, as_version=4)

    parts = []

    for cell in nb.cells:
        if cell.cell_type == "markdown":
            parts.append(cell.source)

    return "\n\n".join(parts)


def find_git_repos(root):
    for p in root.rglob(".git"):
        yield p.parent


def iter_files(repo):
    for p in repo.rglob("*"):
        if not p.is_file():
            continue

        if any(part in SKIP_DIRS for part in p.parts):
            continue

        yield p


def build_records(repo, path, mode, cfg):

    suffix = path.suffix.lower()

    text = None
    kind = None

    try:
        if suffix in {".md", ".txt", ".rst"}:
            text = path.read_text(errors="ignore")
            kind = "docs"

        elif suffix == ".java":

            raw = path.read_text(errors="ignore")

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

            text = path.read_text(errors="ignore")
            kind = "text_full"

    except Exception:
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
    parser.add_argument("--config", required=True)

    args = parser.parse_args()

    with open(args.config) as f:
        cfg = yaml.safe_load(f)

    repo_cfg = cfg["repos"]

    root = Path(repo_cfg["root_dir"]).resolve()

    repos = list(find_git_repos(root))

    print("repos found:", len(repos))

    records = []

    for repo in repos:

        for path in iter_files(repo):

            recs = build_records(
                repo,
                path,
                repo_cfg["mode"],
                repo_cfg,
            )

            records.extend(recs)

    ds = Dataset.from_list(records)

    output_dir = repo_cfg["output_dir"]

    ds.save_to_disk(output_dir)

    print(
        json.dumps(
            {
                "records": len(ds),
                "repos": len(repos),
                "output_dir": output_dir,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
    