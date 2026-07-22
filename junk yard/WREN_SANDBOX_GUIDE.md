# Wren AI — Local Sandbox Setup Guide

A complete, plain-English record of what this sandbox is, how it was built, and how to run it.
Goal: **ask questions in English → get SQL → run it on our office MySQL**, running 100% locally and free.

---

## 1. The mental model (explain it in one breath)

Three separate things — don't mix them up:

| Thing | What it is | Analogy |
|---|---|---|
| **GGUF model** | A single AI brain (a file). Turns text → text. | An **engine** |
| **Wren AI** | A full app *around* the brain: website + schema engine + DB connector + vector search + orchestrator. | The whole **car** |
| **Docker** | Packages & runs Wren's many parts with one command, on our own PC. | The **factory** that assembles the car |

> The GGUF is just *one small part* Wren calls when it needs to think. Wren does everything else.

**Why Docker (and not "just run it" or Colab)?**
- Wren is **5–6 programs** in different languages. Docker runs them together, correctly versioned, in one command — still 100% **local** on our machine.
- **Colab is wrong**: it's temporary (wipes after hours) and lives in Google's cloud, so it **cannot reach our private office database**. Local Docker can.

---

## 2. Architecture (what's actually running)

```
   YOU (browser)
        │  http://localhost:3000
        ▼
 ┌──────────────┐     ┌───────────────────┐
 │   wren-ui    │────▶│  wren-ai-service  │──┐  (orchestrator: turns question → SQL)
 │ (the website)│     └───────────────────┘  │
 └──────┬───────┘            │  ▲             │  calls the AI brain over the network
        │                    ▼  │             ▼
        │            ┌──────────────┐   ┌─────────────────────────────┐
        │            │    qdrant    │   │  OLLAMA (on Windows host)   │
        │            │ (vector DB / │   │  • wren-sql-model  (LLM)    │
        │            │  schema search)│  │  • nomic-embed-text (embed) │
        │            └──────────────┘   └─────────────────────────────┘
        ▼                    ▲                 host.docker.internal:11434
 ┌──────────────┐           │
 │ wren-engine  │           │ semantic layer (understands our tables)
 │ + ibis-server│───────────┘
 └──────┬───────┘
        │  connects over office network
        ▼
   OFFICE MySQL  (our real data)

 (bootstrap = one-shot setup container; runs once then exits — this is normal)
```

**The 6 containers and why each exists:**
- **wren-ui** — the website we click (localhost:3000)
- **wren-ai-service** — the brain-caller: turns our question into SQL using the LLM
- **qdrant** — vector database; lets the AI search our schema to find the right tables
- **wren-engine** — semantic layer; stores our table model, understands the schema
- **ibis-server** — the actual MySQL connector; runs queries against the office DB
- **bootstrap** — runs once to initialise engine config, then exits(0) — *not an error*

The **LLM + embedder do NOT run in Docker** — they run in **Ollama on the Windows host**, and the containers reach them over `host.docker.internal:11434`.

---

## 3. Hardware reality → why the small model

This machine: **4GB VRAM (GTX 1660 Ti), 16GB RAM (mostly used), Docker + Ollama sharing it.**

Rule: to be *fast* (not a snail), the model must fit **entirely in the 4GB VRAM**. Anything bigger spills into RAM and crawls.

- ✅ **Chosen LLM:** `Qwen2.5-Coder-3B-Instruct Q8` (3.4GB) → fits in VRAM, stays fast, good at SQL + JSON.
- ✅ **Embedder:** `nomic-embed-text` (768-dim vectors).
- ❌ Avoided 7B/12B/14B models — too big for 4GB, would spill to RAM.

> Trade-off to remember: **fast + local + 4GB = a small model.** A 3B gives rougher SQL than a big cloud model. The fix isn't a bigger model (won't fit) — it's **feeding Wren clean, denormalized views with readable names** (see `attendance_view.sql`).

---

## 4. Steps performed (in order)

1. **Installed Docker Desktop** (already running: Docker 29.x, Compose v5).
2. **Installed Ollama** on the host (the winget download stalled, so we pulled the installer directly from GitHub and ran it silently).
3. **Configured Ollama for Docker access:** set User env var `OLLAMA_HOST=0.0.0.0` and (re)started `ollama serve` so it listens on all interfaces (`0.0.0.0:11434`) — otherwise containers can't reach it.
4. **Loaded the models into Ollama:**
   - `ollama create wren-sql-model -f Modelfile` (imports the local 3B GGUF)
   - `ollama pull nomic-embed-text`
   - Verified: LLM returns SQL, embedder returns 768-dim vectors.
5. **Discovered the WrenAI repo had restructured** (new "v5" architecture; classic app removed from `main`). So we fetched the **official** `docker-compose.yaml`, `.env`, and `config.yaml` from the matching git commit and **pinned exact versions** (below) instead of `:latest`.
6. **Wrote the corrected project files** (originals backed up in `backup_original/`).
7. **Capped WSL memory** (`C:\Users\Asus\.wslconfig` → 8GB) so Docker and Ollama don't starve each other.
8. **Launched the stack:** `docker compose up -d` (one network hiccup mid-download; retried and it completed).
9. **Fixed one config bug:** the provider wants `api_key_name` (an env-var *name*), not a literal `api_key`. Set `OPENAI_API_KEY=ollama` in `.env` and referenced it via `api_key_name: OPENAI_API_KEY`.
10. **Verified everything green:** all containers up, ai-service reaches Ollama and sees both models, UI responds HTTP 200.

**Pinned image versions (verified to exist together):**
`wren-ai-service 0.29.0 · wren-engine 0.22.0 · wren-engine-ibis 0.22.0 · wren-ui 0.32.2 · wren-bootstrap 0.1.5 · qdrant v1.15.0`

---

## 5. Files in this folder

| File | Purpose |
|---|---|
| `docker-compose.yaml` | Defines & wires the 6 containers (uses versions/ports from `.env`) |
| `.env` | Pinned image versions, ports, dummy `OPENAI_API_KEY`, telemetry off |
| `config.yaml` | Wren's brain config: points LLM + embedder at Ollama; all 34 pipelines; 768 dims |
| `Modelfile` | Recipe to import the local GGUF into Ollama as `wren-sql-model` (plain instruct, temp 0, ctx 4096) |
| `attendance_view.sql` | Example of an LLM-friendly denormalized view (best-practice reference) |
| `data/` | Local storage mounted into the stack |
| `backup_original/` | Your first hand-written files, kept for reference |
| `docker-compose.yml.old` | The original (broken) compose, renamed so Docker won't use it |

---

## 6. Everyday operations (cheat sheet)

Run these from `d:\Wren.ai` in PowerShell:

```powershell
# Start everything
docker compose up -d

# See status of all containers
docker compose ps -a

# Watch logs (the AI brain)
docker compose logs wren-ai-service -f

# Stop everything (keeps data)
docker compose down

# Stop AND wipe all data (fresh start)
docker compose down -v

# Restart just the AI service (e.g. after editing config.yaml)
docker compose up -d --force-recreate wren-ai-service
```

**Ollama must be running** whenever you use Wren:
```powershell
ollama list          # should show wren-sql-model + nomic-embed-text
ollama serve         # if the server isn't running
```

Open the app at **http://localhost:3000**.

---

## 7. Troubleshooting (things that actually bit us)

| Symptom | Cause / Fix |
|---|---|
| `bootstrap Exited (0)` | ✅ Normal — it's a one-shot setup container. |
| `No project found` in ai-service logs | ✅ Normal until you connect a database in the UI. |
| ai-service crashes: *multiple values for `api_key`* | Use `api_key_name: OPENAI_API_KEY` in `config.yaml`, not a literal `api_key`. |
| ai-service can't reach the model | Ollama not on `0.0.0.0` — set `OLLAMA_HOST=0.0.0.0` and restart Ollama. |
| Pull fails: `unexpected EOF` | Network hiccup — just re-run `docker compose pull`; it resumes. |
| Everything slow / freezing | RAM pressure — close Chrome tabs; the `.wslconfig` cap helps. |
| `litellm ... OpenAIException` | NOT real OpenAI — it's just the API dialect name. Ollama (local) raised it. Read the inner message for the real cause. |
| `exceeds the available context size` | Prompt bigger than the model's context. Raise `num_ctx` in `Modelfile` **and** `context_window_size` in `config.yaml` (both now 8192), then recreate the model + restart ai-service. |
| `not enough space on disk` (model create) | C: is nearly full. Ollama models are relocated to **E:** via env var `OLLAMA_MODELS=E:\ollama-models`. Keep large files off C:. |
| Office DB "connection refused/timeout" | Not a Wren problem — must be on office network/VPN, and the MySQL user must be allowed to connect from this machine's IP. |

---

## 8. Next step (not done yet)

1. Open **http://localhost:3000**.
2. Onboarding → choose **MySQL** → enter office DB **host, port (3306), database, username, password** (type the password directly in the UI).
3. Make sure you're **on the office network/VPN** and the DB user can connect **remotely**.
4. Select the tables/views to model, let Wren **index the schema** (first time is slower), then ask questions in English.
5. For best results with the small model, point Wren at **clean denormalized views** (like `attendance_view.sql`), not raw complex tables.

---

*Setup completed 2026-07-19. Stack healthy; database connection is the remaining step.*
