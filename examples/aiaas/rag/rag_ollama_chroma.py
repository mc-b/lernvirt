import os
import re
import json
import hashlib
from dataclasses import dataclass
from typing import Iterable, List, Dict, Optional, Tuple

import requests
from tqdm import tqdm
from pypdf import PdfReader

import chromadb
from chromadb.config import Settings


# -----------------------
# Konfiguration
# -----------------------
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://10.10.1.10:11434")
CHAT_MODEL = os.environ.get("OLLAMA_CHAT_MODEL", "llama3.1:8b-instruct-q4_K_M")
EMBED_MODEL = os.environ.get("OLLAMA_EMBED_MODEL", "nomic-embed-text")

PERSIST_DIR = os.environ.get("CHROMA_DIR", "./chroma_db")
COLLECTION_NAME = os.environ.get("CHROMA_COLLECTION", "docs")

# Chunking-Defaults (bewusst simpel)
CHUNK_SIZE = 900          # Zeichen
CHUNK_OVERLAP = 150       # Zeichen
TOP_K = 6                 # wie viele Chunks werden als Kontext verwendet


# -----------------------
# Hilfsfunktionen
# -----------------------
def sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8", errors="ignore")).hexdigest()

def iter_files(root: str) -> Iterable[str]:
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            yield os.path.join(dirpath, fn)

def is_text_file(path: str) -> bool:
    ext = os.path.splitext(path.lower())[1]
    return ext in {".md", ".txt", ".py", ".js", ".ts", ".java", ".go", ".rs", ".yaml", ".yml", ".json", ".xml", ".html", ".css", ".sh"}

def clean_text(s: str) -> str:
    s = s.replace("\x00", " ")
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()

def chunk_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> List[str]:
    text = clean_text(text)
    if not text:
        return []
    chunks = []
    start = 0
    n = len(text)
    while start < n:
        end = min(n, start + chunk_size)
        chunk = text[start:end]
        chunks.append(chunk)
        if end == n:
            break
        start = max(0, end - overlap)
    return chunks

def read_pdf(path: str) -> str:
    reader = PdfReader(path)
    pages = []
    for p in reader.pages:
        try:
            pages.append(p.extract_text() or "")
        except Exception:
            pages.append("")
    return "\n".join(pages)

def read_text(path: str) -> str:
    # robustes Einlesen für Repos
    for enc in ("utf-8", "utf-8-sig", "latin-1"):
        try:
            with open(path, "r", encoding=enc, errors="ignore") as f:
                return f.read()
        except Exception:
            continue
    return ""


# -----------------------
# Ollama API
# -----------------------
def ollama_embed(texts: List[str]) -> List[List[float]]:
    """
    Nutzt Ollama Embeddings API: POST /api/embeddings
    Pro Call 1 Text (Ollama kann auch batchen je nach Version – hier bewusst simpel/robust).
    """
    out: List[List[float]] = []
    for t in texts:
        r = requests.post(
            f"{OLLAMA_BASE_URL}/api/embeddings",
            json={"model": EMBED_MODEL, "prompt": t},
            timeout=120,
        )
        r.raise_for_status()
        data = r.json()
        out.append(data["embedding"])
    return out

def ollama_chat(prompt: str) -> str:
    """
    Nutzt OpenAI-kompatibles Chat Endpoint von Ollama: POST /v1/chat/completions
    """
    r = requests.post(
        f"{OLLAMA_BASE_URL}/v1/chat/completions",
        json={
            "model": CHAT_MODEL,
            "temperature": 0.2,
            "messages": [
                {"role": "system", "content": "Antworte präzise. Falls der Kontext nicht reicht, sage das klar."},
                {"role": "user", "content": prompt},
            ],
        },
        timeout=300,
    )
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


# -----------------------
# Chroma Storage
# -----------------------
def get_collection():
    client = chromadb.PersistentClient(path=PERSIST_DIR, settings=Settings(anonymized_telemetry=False))
    col = client.get_or_create_collection(name=COLLECTION_NAME, metadata={"hnsw:space": "cosine"})
    return col

@dataclass
class DocChunk:
    id: str
    text: str
    meta: Dict[str, str]

def build_chunks_from_inputs(paths: List[str]) -> List[DocChunk]:
    chunks: List[DocChunk] = []
    for p in paths:
        if os.path.isdir(p):
            for f in iter_files(p):
                # Skip grosses / irrelevantes
                bn = os.path.basename(f)
                if bn.startswith(".") or "/.git/" in f or "/node_modules/" in f or "/dist/" in f or "/build/" in f:
                    continue
                if f.lower().endswith(".pdf"):
                    txt = read_pdf(f)
                    parts = chunk_text(txt)
                    for i, c in enumerate(parts):
                        cid = sha1(f"{f}::pdf::{i}::{c[:80]}")
                        chunks.append(DocChunk(id=cid, text=c, meta={"source": f, "type": "pdf", "chunk": str(i)}))
                elif is_text_file(f):
                    txt = read_text(f)
                    parts = chunk_text(txt)
                    for i, c in enumerate(parts):
                        cid = sha1(f"{f}::text::{i}::{c[:80]}")
                        chunks.append(DocChunk(id=cid, text=c, meta={"source": f, "type": "text", "chunk": str(i)}))
        else:
            if p.lower().endswith(".pdf"):
                txt = read_pdf(p)
                parts = chunk_text(txt)
                for i, c in enumerate(parts):
                    cid = sha1(f"{p}::pdf::{i}::{c[:80]}")
                    chunks.append(DocChunk(id=cid, text=c, meta={"source": p, "type": "pdf", "chunk": str(i)}))
            else:
                txt = read_text(p)
                parts = chunk_text(txt)
                for i, c in enumerate(parts):
                    cid = sha1(f"{p}::text::{i}::{c[:80]}")
                    chunks.append(DocChunk(id=cid, text=c, meta={"source": p, "type": "text", "chunk": str(i)}))
    return chunks

def upsert_chunks(col, chunks: List[DocChunk]) -> None:
    if not chunks:
        print("Keine Chunks gefunden.")
        return

    # existierende IDs rausfiltern (einfacher Ansatz: try add, bei Duplikat ignorieren ist je nach Chroma-Version unterschiedlich)
    # hier: wir batchen und verlassen uns darauf, dass IDs stabil sind (bei erneutem ingest werden sie überschrieben via upsert-ähnlich)
    batch_size = 64
    for i in tqdm(range(0, len(chunks), batch_size), desc="Indexing"):
        batch = chunks[i:i+batch_size]
        texts = [b.text for b in batch]
        ids = [b.id for b in batch]
        metas = [b.meta for b in batch]
        embs = ollama_embed(texts)
        # Chroma: add erlaubt keine doppelten IDs; wir versuchen delete+add für stabile Re-Indexierung
        try:
            col.delete(ids=ids)
        except Exception:
            pass
        col.add(documents=texts, embeddings=embs, metadatas=metas, ids=ids)

def retrieve(col, question: str, k: int = TOP_K) -> Tuple[List[str], List[Dict[str, str]]]:
    q_emb = ollama_embed([question])[0]
    res = col.query(query_embeddings=[q_emb], n_results=k, include=["documents", "metadatas", "distances"])
    docs = res.get("documents", [[]])[0]
    metas = res.get("metadatas", [[]])[0]
    return docs, metas

def make_prompt(question: str, docs: List[str], metas: List[Dict[str, str]]) -> str:
    ctx_blocks = []
    for d, m in zip(docs, metas):
        src = m.get("source", "unknown")
        ch = m.get("chunk", "?")
        ctx_blocks.append(f"[Quelle: {src} | Chunk: {ch}]\n{d}")
    context = "\n\n---\n\n".join(ctx_blocks) if ctx_blocks else "(Kein Kontext gefunden)"

    return (
        "Beantworte die Frage nur anhand des Kontexts.\n"
        "Wenn der Kontext nicht genügt, sage explizit, dass es nicht im Material steht.\n\n"
        f"KONTEXT:\n{context}\n\n"
        f"FRAGE:\n{question}\n\n"
        "ANTWORT:"
    )


# -----------------------
# CLI
# -----------------------
def main():
    import argparse

    parser = argparse.ArgumentParser(description="Minimal RAG: PDF/Repo -> Chroma -> Ollama Chat")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_ingest = sub.add_parser("ingest", help="Indexiert PDFs/Repos in Chroma")
    p_ingest.add_argument("paths", nargs="+", help="Pfad(e) zu PDF(s) oder Verzeichnis(sen)")

    p_ask = sub.add_parser("ask", help="Stellt eine Frage gegen den Index")
    p_ask.add_argument("question", help="Frage")
    p_ask.add_argument("--k", type=int, default=TOP_K, help="Top-K Chunks")

    args = parser.parse_args()
    col = get_collection()

    if args.cmd == "ingest":
        chunks = build_chunks_from_inputs(args.paths)
        print(f"Chunks: {len(chunks)}")
        upsert_chunks(col, chunks)
        print("Fertig.")
        return

    if args.cmd == "ask":
        docs, metas = retrieve(col, args.question, k=args.k)
        prompt = make_prompt(args.question, docs, metas)
        answer = ollama_chat(prompt)
        print("\n" + answer.strip() + "\n")
        # optional: Quellen anzeigen
        if metas:
            print("Verwendete Quellen:")
            seen = set()
            for m in metas:
                s = m.get("source", "unknown")
                if s not in seen:
                    print(f"- {s}")
                    seen.add(s)

if __name__ == "__main__":
    main()

