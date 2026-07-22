# Wren AI Local Sandbox — Project Handover

> **Purpose of this doc:** a complete, self-contained record so anyone (a new chat
> session, a teammate, or future-you) can understand the whole project and continue
> without prior context. Read top to bottom.

- **Last updated:** 2026-07-19
- **Location of everything:** `d:\Wren.ai`
- **One-line status:** ✅ Full stack is built, running and healthy on local Docker + host Ollama. ⏳ The only remaining step is connecting the office MySQL database in the UI.

---

## 0. START HERE — resume checklist (do this first in a new session)

To bring the sandbox back up after a reboot:

```powershell
# 1. Make sure Ollama is running and can serve (host must expose 0.0.0.0)
ollama list          # should show: wren-sql-model, nomic-embed-text
#   if not running:  ollama serve      (leave it running)

# 2. Start Docker Desktop (auto-starts on login; wait ~1-2 min until ready)

# 3. Start the Wren stack
cd d:\Wren.ai

docker compose up -d
# 4. Confirm health
docker compose ps -a          # all "running" except bootstrap = Exited(0) (normal)

# 5. Open the app
#    http://localhost:3000
```

Expected total time: **~2-4 minutes** (mostly Docker booting). Nothing needs
reinstalling or re-downloading — images and models are cached on disk.

**Then continue with Section 7 (connect the office MySQL) — that's the pending work.**

---

## 1. What this project is (the mental model)

Goal: **ask questions in plain English → get SQL → run it on our office MySQL**, 100% local and free.

Three separate things — don't confuse them:

| Thing | What it is | Analogy |
|---|---|---|
| **GGUF model** | One AI brain (a file). Text in → text out. | An **engine** |
| **Wren AI** | A full app *around* the brain: website + schema engine + DB connector + vector search + orchestrator | The whole **car** |
| **Docker** | Runs Wren's many parts together with one command, locally | The **factory** |

- **Why Docker (not "just run it")?** Wren is 5–6 programs in different languages; Docker runs them together, correctly versioned, still 100% local.
- **Why not Colab?** Colab is temporary and cloud-hosted — it can't reach our private office database. Local Docker can.

---

## 2. Current status

### ✅ Done and verified
- Docker Desktop installed & running (Docker 29.6.1, Compose v5.3.0)
- Ollama installed & running, reachable by containers
- Both models loaded and tested (LLM returns SQL, embedder returns 768-dim vectors)
- All 6 Wren containers up and healthy
- ai-service loads config, builds all 34 pipelines, and reaches Ollama
- UI responds at localhost:3000
- Context-size bug fixed (see §6) — large prompts now work

### ⏳ Not done yet
- **Connecting the office MySQL database** (Section 7) — the last step
- Modeling a view/tables in Wren and running the first real text-to-SQL query

---

## 3. Architecture

```
   YOU (browser)
        │  http://localhost:3000
        ▼
 ┌──────────────┐     ┌───────────────────┐
 │   wren-ui    │────▶│  wren-ai-service  │──┐  (orchestrator: question → SQL)
 │ (the website)│     └───────────────────┘  │  calls the AI brain over the network
 └──────┬───────┘            │  ▲             ▼
        │                    ▼  │      ┌─────────────────────────────┐
        │            ┌──────────────┐  │  OLLAMA (Windows host)      │
        │            │   qdrant     │  │  • wren-sql-model  (LLM)    │
        │            │ (vector DB)  │  │  • nomic-embed-text (embed) │
        │            └──────────────┘  └─────────────────────────────┘
        ▼                                 host.docker.internal:11434
 ┌──────────────┐
 │ wren-engine  │  semantic layer (understands our tables)
 │ + ibis-server│──────────▶  OFFICE MySQL  (our real data)
 └──────────────┘
 (bootstrap = one-shot setup container; runs once, exits(0) — normal)
```

The **6 containers** (all in `docker-compose.yaml`):
- **wren-ui** — the website (localhost:3000)
- **wren-ai-service** — turns questions into SQL using the LLM
- **qdrant** — vector DB; lets the AI search the schema
- **wren-engine** — semantic layer; stores the table model
- **ibis-server** — the actual MySQL connector; runs queries
- **bootstrap** — one-shot init; exits(0) after setup (not an error)

> The **LLM + embedder do NOT run in Docker** — they run in **Ollama on the Windows host**, reached via `host.docker.internal:11434`.

---

## 4. Machine & environment state (exact, for reproducing/debugging)

**Hardware:** GTX 1660 Ti (**4GB VRAM**), **16GB RAM** (mostly used), Windows 11.
This is why we use a **small 3B model** — to be fast it must fit fully in 4GB VRAM.

**Ollama (on host):**
- Installed at `C:\Users\Asus\AppData\Local\Programs\Ollama\ollama.exe` (v0.32.1)
- **Persistent User env vars** (survive reboot):
  - `OLLAMA_HOST=0.0.0.0`  ← lets containers reach Ollama (not just localhost)
  - `OLLAMA_MODELS=E:\ollama-models`  ← models live on **E:** because C: is nearly full
- Started with `ollama serve`. On reboot the tray app should auto-start and read these env vars.
- **Models** (stored on `E:\ollama-models`):
  - `wren-sql-model` — from `E:\AI MODELS\Qwen\Qwen2.5-Coder-3B-Instruct-GGUF\qwen2.5-coder-3b-instruct-q8_0.gguf`; `num_ctx 8192`, `temperature 0`, plain instruct (no SQL system prompt)
  - `nomic-embed-text` — 768-dim embeddings

**Docker:**
- Stack lives in `d:\Wren.ai`, uses a named volume `wrenai_data` (persists across restarts)
- Restart policy is `on-failure` → the stack does **not** auto-start on reboot; run `docker compose up -d`
- **Pinned image versions** (verified to exist together — do NOT switch to `:latest`):
  `wren-ai-service 0.29.0 · wren-engine 0.22.0 · wren-engine-ibis 0.22.0 · wren-ui 0.32.2 · wren-bootstrap 0.1.5 · qdrant v1.15.0` (WREN_PRODUCT_VERSION 0.29.1)

**WSL:** `C:\Users\Asus\.wslconfig` caps the Docker VM at `memory=8GB, processors=4, swap=2GB` so Docker and Ollama don't starve each other.

**Disk:** C: ~458GB total, was critically low (~2GB free); after moving models to E: and cleanup it's ~8GB free. **E:** has ~228GB free — keep large files (models, downloads) there.

---

## 5. Files in `d:\Wren.ai`

| File / folder | Purpose |
|---|---|
| `docker-compose.yaml` | Defines & wires the 6 containers (versions/ports come from `.env`) |
| `.env` | Pinned image versions, ports, `OPENAI_API_KEY=ollama` (dummy), telemetry off |
| `config.yaml` | Wren's brain config: LLM + embedder → Ollama, all 34 pipelines, dim 768, tuned settings |
| `Modelfile` | Recipe to import the local GGUF into Ollama as `wren-sql-model` (plain instruct, temp 0, `num_ctx 8192`) |
| `attendance_view.sql` | Example of an LLM-friendly denormalized view (best-practice reference) |
| `data/` | Local storage mounted into the stack |
| `backup_original/` | The very first hand-written files, kept for reference |
| `docker-compose.yml.old` | Original (broken) compose, renamed so Docker won't use it |
| `junk yard/` | Older docs: `WREN_SANDBOX_GUIDE.md`, original `project handover.txt` |
| `PROJECT_HANDOVER.md` | **This document** — the master handover |

---

## 6. Key config decisions & WHY (important context)

These are the non-obvious choices. A new session should understand these before changing anything.

1. **Model = Qwen2.5-Coder-3B Q8**, not a bigger one. 4GB VRAM forces a small model to stay fast. Bigger models spill to RAM = slow. Trade-off: a 3B gives rougher SQL — the fix is **clean denormalized views**, not a bigger model.

2. **Modelfile is a plain instruct import** — no SQL system-prompt, no ``` stop tokens. Wren injects its own prompts and expects JSON back; a restrictive system prompt breaks its pipelines.

3. **`api_key_name`, not `api_key`.** The provider expects the *name of an env var* holding the key. A literal `api_key: ...` crashes the embedder ("multiple values for keyword argument 'api_key'"). We set `OPENAI_API_KEY=ollama` in `.env` and reference it via `api_key_name: OPENAI_API_KEY`. (Ollama ignores the value; the OpenAI client just needs it non-empty.)

4. **"OpenAI" is not real OpenAI.** We route through LiteLLM with the `openai/` prefix because Ollama exposes an OpenAI-*compatible* API (`/v1`). Errors get labeled `OpenAIException` — that's the API dialect name, not the company. Nothing leaves the machine.

5. **Context = 8192.** Wren prompts hit ~6800 tokens and failed at the original 4096 ("exceeds context size"). Raised `num_ctx 8192` (Modelfile) + `context_window_size: 8192` (config). KV cache for 8192 on a 3B is only ~300MB, so it still fits 4GB.

6. **Prompt-trimming settings** (to fit context + speed up the 3B), in `config.yaml` `settings`:
   - `allow_sql_generation_reasoning: false` (drops a big extra reasoning call)
   - `enable_column_pruning: true`
   - `table_retrieval_size: 8`, `table_column_retrieval_size: 50`
   - `langfuse_enable: false` (no keys / private sandbox)

7. **Models on E:, pinned versions, telemetry off** — see §4.

---

## 7. NEXT STEP — connect the office MySQL (the pending work)

1. Open **http://localhost:3000**. The onboarding wizard appears → choose **MySQL**.
2. Enter: **Host/IP, Port (usually 3306), Database, Username, Password** (type the password directly in the UI).
3. **Prerequisites that usually cause failures** (check these first if it won't connect):
   - You must be **on the office network / VPN**.
   - The MySQL user must be allowed to connect **from this machine's IP** (not just localhost) — DBA may need to grant that.
   - Recommended: use a **read-only user** scoped to just the view(s) you expose.
4. **You choose what to import** — Wren reads only schema *metadata* on connect, then lets you pick specific tables/views. It does **not** ingest all data. Data is only queried (with a `LIMIT`) when you ask a question.
5. **Best practice for the small model:** expose **clean denormalized VIEWs** (like `attendance_view.sql` — flattened joins, readable names, decoded codes) and import only those. This both limits exposure and dramatically improves SQL accuracy.
6. After importing, let Wren **index the schema** (first time is slower on the 3B), then ask questions in English.

---

## 8. Daily operations cheat sheet

Run from `d:\Wren.ai` in PowerShell:

```powershell
docker compose up -d                                   # start
docker compose ps -a                                   # status
docker compose logs wren-ai-service -f                 # watch AI logs
docker compose down                                    # stop (keeps data)
docker compose down -v                                 # stop + WIPE data (fresh start)
docker compose up -d --force-recreate wren-ai-service  # after editing config.yaml

ollama list        # verify models present
ollama serve       # if Ollama server isn't running
```

**After editing `Modelfile`** (e.g. context), you must rebuild the model:
```powershell
$env:OLLAMA_HOST="0.0.0.0"; $env:OLLAMA_MODELS="E:\ollama-models"
ollama create wren-sql-model -f d:\Wren.ai\Modelfile
ollama stop wren-sql-model
docker compose up -d --force-recreate wren-ai-service
```

---

## 9. Troubleshooting (gotchas we actually hit)

| Symptom | Cause / Fix |
|---|---|
| `bootstrap Exited (0)` | ✅ Normal — one-shot setup container. |
| `No project found` in ai-service logs | ✅ Normal until a database is connected in the UI. |
| crash: *multiple values for `api_key`* | Use `api_key_name: OPENAI_API_KEY` in `config.yaml`, not a literal `api_key`. |
| `litellm ... OpenAIException` | NOT real OpenAI — just the API dialect name. Read the inner message for the real cause. |
| `exceeds the available context size` | Prompt bigger than context. Raise `num_ctx` (Modelfile) **and** `context_window_size` (config), both now 8192; rebuild model + restart ai-service. |
| `not enough space on disk` (model create) | C: nearly full. Models are on **E:** via `OLLAMA_MODELS=E:\ollama-models`. Keep big files off C:. |
| ai-service can't reach the model | Ollama not on `0.0.0.0` — ensure `OLLAMA_HOST=0.0.0.0`, then `ollama serve`. |
| Pull fails: `unexpected EOF` | Network hiccup — re-run `docker compose pull`; it resumes. |
| Everything slow / freezing | RAM pressure — close Chrome; `.wslconfig` cap helps. |
| Office DB "connection refused/timeout" | Not Wren — must be on office network/VPN + user allowed to connect from this machine's IP. |
| Image name `wren-ibis-server` denied | Correct name is `wren-engine-ibis`. |

---

## 10. Open items / TODO (not yet done)

- [ ] **Connect the office MySQL** (Section 7) — the main remaining task.
- [ ] **Model a curated view** and run the first text-to-SQL query.
- [ ] **Optional: auto-start the stack on boot** — change each service's `restart: on-failure` to `restart: unless-stopped` in `docker-compose.yaml` so the stack comes up with Docker (skip the manual `docker compose up -d`).
- [ ] **Disk cleanup pending decision:** Recycle Bin holds ~33.6 GB (emptying is permanent — user has not confirmed). Downloads folder ~5.5 GB of personal files. Neither was deleted.
- [ ] **Ollama startup:** currently relies on the tray app reading env vars after reboot. If the model is ever unreachable, run `ollama serve` once.

---

## 11. Quick facts to sound sharp explaining it

- "The GGUF is the **brain**, Wren is the **car**, Docker is the **factory**."
- Wren only reads schema **metadata**, not your data; you **choose** which tables/views to import.
- `bootstrap Exited(0)` and `No project found` are **normal**, not errors.
- On 4GB VRAM: **fast + local = a small model**; quality comes from **clean views**, not a bigger model.
- "OpenAIException" ≠ OpenAI — it's just the local Ollama call in OpenAI format.

*End of handover.*
