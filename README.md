# Siksh Setu Chatbot — Wren AI Text-to-SQL Sandbox

Ask questions in plain English → get SQL → run it against our office MySQL database.

This repo holds the configuration for a self-hosted [Wren AI](https://github.com/Canner/WrenAI)
deployment: a natural-language-to-SQL assistant that runs on our own hardware, connects to our
private office database, and uses a hybrid AI backend (cloud LLM + local embedder).

> **Status:** ✅ Full stack builds, runs, and is healthy on local Docker.
> ⏳ Remaining step on first setup: connect the office MySQL database in the UI (see [§7](#7-connect-the-office-mysql)).

---

## 1. What this is (the mental model)

Three separate things — don't mix them up:

| Thing | What it is | Analogy |
|---|---|---|
| **The LLM** | An AI brain that turns text → SQL and phrases answers. | The **engine** |
| **Wren AI** | The full app *around* the brain: website + schema engine + DB connector + vector search + orchestrator. | The whole **car** |
| **Docker** | Packages & runs Wren's many parts with one command, on our own machine. | The **factory** that assembles the car |

Wren does everything except the raw "thinking" — that it delegates to an LLM, and to an **embedder**
(a smaller model that turns text into number-vectors for schema search).

**Why Docker (not "just run it" or Colab)?**
- Wren is 5–6 programs in different languages. Docker runs them together, correctly versioned, in one command — 100% local.
- **Colab won't work:** it's temporary and cloud-hosted, so it **cannot reach our private office database**. Local Docker can.

---

## 2. Architecture

```
   YOU (browser)
        │  http://localhost:3000
        ▼
 ┌──────────────┐     ┌───────────────────┐
 │   wren-ui    │────▶│  wren-ai-service  │──┐  (orchestrator: turns question → SQL)
 │ (the website)│     └───────────────────┘  │
 └──────┬───────┘            │  ▲             │  calls the AI over the network
        │                    ▼  │             ▼
        │            ┌──────────────┐   ┌──────────────────────────────────────┐
        │            │    qdrant    │   │  AI backend (HYBRID):                │
        │            │ (vector DB / │   │  • LLM      → Google Gemini (cloud)  │
        │            │ schema search)│  │  • Embedder → local Ollama           │
        │            └──────────────┘   │                (nomic-embed-text)    │
        ▼                    ▲          └──────────────────────────────────────┘
 ┌──────────────┐           │            embedder @ host.docker.internal:11434
 │ wren-engine  │           │
 │ + ibis-server│───────────┘ semantic layer (understands our tables)
 └──────┬───────┘
        │  connects over office network
        ▼
   OFFICE MySQL  (our real data)

 (bootstrap = one-shot setup container; runs once then exits(0) — this is normal)
```

### The containers and why each exists
- **wren-ui** — the website we click (`localhost:3000`)
- **wren-ai-service** — the orchestrator: turns our question into SQL using the LLM + embedder
- **qdrant** — vector database; lets the AI search our schema to find the right tables
- **wren-engine** — semantic layer; stores our table model, understands the schema
- **ibis-server** — the actual MySQL connector; runs queries against the office DB
- **bootstrap** — runs once to initialise engine config, then exits(0) — *not an error*

---

## 3. The AI backend (hybrid) — important

Wren uses **two different AI jobs**, and they run in **two different places**:

| Job | What it does | Runs on | Configured in |
|---|---|---|---|
| **LLM** | Writes the SQL, reads the DB result, phrases the answer | **Google Gemini** (cloud, via LiteLLM `gemini/` provider) | `config.yaml` → `type: llm` |
| **Embedder** | Turns schema + your question into 768-dim vectors so qdrant can find the *right tables* | **Local Ollama** (`nomic-embed-text`) | `config.yaml` → `type: embedder` |

**Why the embedder is local (and why Ollama must be running):**
Before Gemini ever writes SQL, Wren has to pick *which* tables to send it. It does that by embedding
your question and matching it against embedded schema in qdrant. That embedding step is served by
Ollama. **If Ollama is down, every request fails** with `openai.APIConnectionError: Connection error`
in the retrieval step — even though Gemini itself is fine. (See [Troubleshooting](#9-troubleshooting).)

> Keeping the embedder on local Ollama is deliberate: embeddings are free and lightweight
> (`nomic-embed-text` is only 137M params), so they cost **zero** Gemini tokens.

---

## 4. Prerequisites

- **Docker Desktop** (Docker 29.x / Compose v5 verified).
- **Ollama** installed on the host, serving the embedder.
  - Set a user env var `OLLAMA_HOST=0.0.0.0` so containers can reach it (not just localhost).
  - Pull the embedder: `ollama pull nomic-embed-text`
- **A Google AI Studio key** for Gemini (free tier works). Paste it into `.env` as `GEMINI_API_KEY`.
- Network access to the **office MySQL** (VPN / office network), and a MySQL user allowed to connect
  from this machine's IP.

> **Optional (100%-local mode):** import a local GGUF SQL model into Ollama (see `Modelfile`) and point
> the LLM at it instead of Gemini. The previous fully-local config is preserved in `backup_ollama_*`.

---

## 5. Quick start

```powershell
# 1. Create your .env from the template and paste your Gemini key
copy .env.example .env
#    → edit .env, set GEMINI_API_KEY=<your key>

# 2. Make sure Ollama is running and serving the embedder
$env:OLLAMA_HOST = "0.0.0.0"
ollama serve            # (run in its own window, or as a background process)
ollama pull nomic-embed-text

# 3. Launch the stack
docker compose up -d

# 4. Open the UI
start http://localhost:3000
```

Then follow the onboarding wizard to [connect the office MySQL](#7-connect-the-office-mysql).

---

## 6. Configuration

| File | Purpose |
|---|---|
| `docker-compose.yaml` | Defines & wires the containers (versions/ports come from `.env`) |
| `.env` | **Not committed.** Real secrets: `GEMINI_API_KEY`, pinned image versions, ports, telemetry off |
| `.env.example` | Template with the same keys, secrets blanked — copy to `.env` |
| `config.yaml` | Wren's brain config: LLM → Gemini, embedder → Ollama, all 34 pipelines, 768 dims |
| `Modelfile` | Recipe to import a local GGUF SQL model into Ollama (for fully-local mode) |
| `attendance_view.sql` | Example of an LLM-friendly denormalized view (best-practice reference) |

**Pinned image versions** (verified to co-exist — do **not** use `:latest`):

```
wren-ai-service 0.29.0 · wren-engine 0.22.0 · wren-engine-ibis 0.22.0
wren-ui 0.32.2 · wren-bootstrap 0.1.5 · qdrant v1.15.0
```

### Key config notes
- The LLM block uses `model: gemini/gemini-3.1-flash-lite` with `api_key_name: GEMINI_API_KEY`
  (an env-var **name**, not the literal key).
- The embedder block points at `http://host.docker.internal:11434/v1` (Ollama on the host).
- `embedding_model_dim: 768` matches `nomic-embed-text`. **If you change the embedder model, this must
  change too, and qdrant must be re-indexed.**
- Reasoning pipelines are off (`allow_sql_generation_reasoning: false`) and column pruning is on to keep
  prompts small — tuned for a small model / low token budget.

---

## 7. Connect the office MySQL

1. Open **http://localhost:3000** → onboarding wizard → choose **MySQL**.
2. Enter **Host/IP, Port (usually 3306), Database, Username, Password** (typed directly in the UI).
3. The MySQL user must be allowed to connect **from this machine's IP** (a DBA may need to grant that).
4. **You choose which tables/views to import.** Wren reads only schema *metadata* on connect — it does
   **not** ingest all your data. Data is only queried (with a `LIMIT`) when you ask a question.
5. Let Wren **index the schema** (first time is slower), then ask questions in English.

> These connection details are stored by Wren under `data/` (a local SQLite metadata store).
> `data/` is **gitignored** and never pushed — that's where DB credentials live.

---

## 8. Everyday operations (cheat sheet)

Run from the repo root in PowerShell:

```powershell
docker compose up -d                                   # Start everything
docker compose ps -a                                   # Status of all containers
docker compose logs wren-ai-service -f                 # Watch the orchestrator logs
docker compose down                                    # Stop (keeps data)
docker compose down -v                                 # Stop AND wipe all data (fresh start)
docker compose up -d --force-recreate wren-ai-service  # Restart AI service after editing config.yaml
```

**Ollama must be running whenever you use Wren.** Quick check:

```powershell
curl.exe -s http://localhost:11434/api/tags            # should list nomic-embed-text
```

---

## 9. Troubleshooting

| Symptom | Cause & fix |
|---|---|
| `openai.APIConnectionError: Connection error` in ai-service logs, failing at the **embedding** step (`db_schema_retrieval.py`) | **Ollama is down or unreachable.** Start it: `$env:OLLAMA_HOST="0.0.0.0"; ollama serve`. Verify host: `curl.exe -s http://localhost:11434/api/tags`. Verify from container: it must reach `host.docker.internal:11434`. |
| ai-service can't reach the model | Ollama not bound to `0.0.0.0` — set `OLLAMA_HOST=0.0.0.0`, then restart Ollama. |
| `No project found` in ai-service logs | ✅ Normal until a database is connected in the UI. |
| Office DB "connection refused / timeout" | Not a Wren problem — be on the office network/VPN, and ensure the MySQL user may connect from this machine's IP. |
| bootstrap container "exited" | ✅ Normal — it's a one-shot init container that runs once and exits(0). |
| Rough / wrong SQL | Feed Wren clean, denormalized **views** with readable names + column comments (see `attendance_view.sql`), rather than raw normalized tables. |

---

## 10. Roadmap — planned production migration

The current setup runs on a personal laptop (4GB VRAM) with a small model. The planned move:

- **Wren stack** → a **dedicated Linux server** from DevOps (no GPU needed — the containers are
  CPU-light; the heavy AI is offloaded).
- **LLM** → a large model (**~27–32B**, e.g. Gemma 3 27B / Qwen 32B) served on the office **Mac Studio**
  (unified memory runs big models fast). This replaces both Gemini *and* the tiny local 3B.
- **Embedder** → likely `nomic-embed-text` hosted on the same Mac Studio.
- **Off the personal laptop** entirely — office data on office-owned hardware (security/compliance win).

Architecturally this is the **same diagram** — only the addresses change. The LLM/embedder endpoints in
`config.yaml` point at the Mac Studio's IP over the office network instead of `host.docker.internal`.
Migration is mostly **config + networking**, not a rebuild.

**Open items to confirm with DevOps before migrating:**
- Exact model name + serving stack (Ollama / LM Studio / vLLM) and its IP; must listen on `0.0.0.0` with the firewall open to the server.
- Where the embedder runs, and its `embedding_model_dim` (re-index qdrant if the model changes).
- Network reachability: server → Mac Studio (LLM + embedder), and server → office MySQL (static IPs/hostnames).
- Who keeps the Mac Studio awake with the model loaded; expected concurrency if the whole office uses it.

---

## 11. Security notes

- **`.env` is never committed** — it holds the real `GEMINI_API_KEY`. Only `.env.example` (blanked) is in the repo.
- **`data/` is gitignored** — that's where Wren stores the office MySQL connection, including the password.
- Backups (`backup_ollama_*`, `backup_original`) are gitignored — they contained `.env` copies.
- If a key is ever exposed, rotate it in Google AI Studio and update your local `.env`.

---

## 12. Hardware note

Current sandbox machine: **4GB VRAM (GTX 1660 Ti), 16GB RAM**, sharing resources between Docker and Ollama.
That's why the local-only fallback uses a small 3B SQL model — anything bigger spills out of VRAM and
crawls. The fix for rougher SQL isn't a bigger model that won't fit; it's feeding Wren **clean views with
readable names and column comments** — which the [roadmap](#10-roadmap--planned-production-migration)
hardware upgrade also solves outright.
