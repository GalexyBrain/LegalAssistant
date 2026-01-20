
## Repo description (for GitHub)

A full-stack **legal-case assistant**: a Flask API with JWT auth, lawyer discovery (geo + search), and client↔lawyer messaging, plus an LLM chat endpoint powered by **Gemini + LangChain ReAct + vector search (FAISS)** for answering questions grounded in pre-indexed case PDFs (with citations). Includes a one-time index builder for ingesting case sheets and a Next.js frontend.

---

# README.md

## Legal Case Assistant (Flask + Gemini RAG) + Next.js Frontend

This repo contains a full-stack app that helps **clients** find and message **lawyers**, and optionally chat with an **LLM assistant** that answers questions using **retrieved evidence from indexed case PDFs** (RAG) with page-level citations.

### What’s inside

**Backend (Flask)**

* JWT authentication (register/login/me)
* Role-based access control (client / lawyer)
* Lawyer discovery with:

  * optional text search (`q`) over email + location name
  * optional geo-radius filtering using Haversine distance (`lat`, `lon`, `radius_km`)
* Client ↔ Lawyer messaging:

  * send messages
  * fetch a thread (with cursors)
  * list conversation partners (recent-first)
* LLM chat endpoint (`/chat`):

  * uses **Gemini** via LangChain
  * **retrieves** supporting context from a persisted vector index (FAISS)
  * can accept optional user-provided PDF or raw text as *temporary* context (not stored)

**Indexing / Retrieval**

* A CLI script to build/rebuild the FAISS index from a directory of PDFs (“case sheets”)
* A loader that **requires** the index to exist at startup (`load_vector_store_or_raise`)

**Frontend (Next.js)**

* Next.js client application consuming the Flask API
* Handles auth, discovery, messaging, and chat UI (implementation lives in the frontend folder)

---

## Architecture overview

1. **Case PDFs** are embedded and stored in a persisted **FAISS** index (one-time or periodic rebuild).
2. The `/chat` endpoint uses a LangChain ReAct agent:

   * retrieves top-K relevant chunks from the vector store
   * answers using Gemini, citing sources as `(filename p.#)`
3. Users can also upload a PDF *per chat request*; it is processed and used as transient context (not stored).

---

## Requirements

### Backend

* Python 3.10+ recommended
* Environment variables (see below)
* SQLite (built-in)

### Frontend

* Node.js 18+ recommended
* Next.js app (set up to call the Flask API)

---

## Environment variables (Backend)

Create a `.env` in the backend root:

```env
# Required
GEMINI_API_KEY=your_google_gemini_key

# JWT
JWT_SECRET=change-me-in-prod
JWT_ALGO=HS256
JWT_EXPIRE_HOURS=2

# Paths
UPLOAD_DIR=./uploads
INDEX_DIR=./index
DB_PATH=./app.db

# CORS (comma-separated)
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5173

# Optional (used by indexing script depending on your retrieval module)
CASE_SHEETS_DIR=./case_sheets
EMBED_MODEL=sentence-transformers/all-MiniLM-L6-v2
```

**Important:** the backend will crash on startup if:

* `GEMINI_API_KEY` is missing
* the vector index directory does not exist (because it uses `load_vector_store_or_raise(INDEX_DIR)`)

---

## Setup

### 1) Backend install

```bash
python -m venv .venv
source .venv/bin/activate  # (Windows: .venv\Scripts\activate)
pip install -r requirements.txt
```

> Ensure your `requirements.txt` includes Flask, flask-cors, python-dotenv, PyJWT, Werkzeug, LangChain deps, FAISS deps, etc.

### 2) Build the FAISS index (one-time)

Before running the API, build the index from your case PDFs directory:

```bash
python build_index.py --case_dir ./case_sheets --index_dir ./index
```

(Your repo may name this script differently—use the file that contains `build_or_rebuild_index(...)`.)

### 3) Run the backend

```bash
python api.py
```

Default: `http://0.0.0.0:5000`

---

## Frontend (Next.js)

From the frontend directory:

```bash
npm install
npm run dev
```

Configure the frontend to point at the Flask base URL (commonly via `.env.local`):

```env
NEXT_PUBLIC_API_BASE_URL=http://localhost:5000
```

If you’re using cookies/credentials, tighten CORS origins and avoid `origins="*"` in production.

---

## API usage

### Auth

#### Register

`POST /auth/register`

```json
{
  "email": "user@example.com",
  "password": "secret",
  "role": "client",
  "location_name": "Mumbai",
  "location_lat": 19.0760,
  "location_lon": 72.8777
}
```

Response:

```json
{ "token": "<jwt>", "user": { "...": "..." } }
```

#### Login

`POST /auth/login`

```json
{ "email": "user@example.com", "password": "secret" }
```

Use the token for authenticated routes:

```
Authorization: Bearer <jwt>
```

#### Current user

* `GET /me` → lightweight identity (from token)
* `GET /me/profile` → full user row from DB

#### Update location

`PATCH /me/location`

```json
{
  "location_name": "Pune",
  "location_lat": 18.5204,
  "location_lon": 73.8567
}
```

---

### Lawyer discovery

`GET /lawyers`

Query params:

* `q` (optional): search email + location_name
* `lat`, `lon` (optional): your coordinates
* `radius_km` (optional): filter within radius
* `limit` (optional, default 50, max 200)

Example:

```
/lawyers?lat=19.076&lon=72.8777&radius_km=25&q=mumbai&limit=20
```

Returns lawyers sorted by `distance_km` when available.

---

### Messaging

#### Send message

`POST /messages/send`

```json
{ "to_user_id": 42, "message": "Hi, can you help with my case?" }
```

Rules:

* Messages are only allowed **between a client and a lawyer**
* The system stores `client_id`, `lawyer_id`, and `sender_id`

#### Get message thread

`GET /messages/thread?with_user_id=42&limit=100`

Optional cursors:

* `before_id`
* `after_id`

Response:

```json
{ "messages": [ { "id": 1, "message": "...", "created_at": "..." } ] }
```

#### List conversation partners

`GET /messages/partners?limit=100`

Returns distinct partners with last message metadata.

---

### LLM Chat (RAG)

`POST /chat`

Supports **JSON** and **multipart/form-data**.

#### JSON

```json
{
  "message": "Summarize the key issues in the case and likely defenses.",
  "session_id": "abc123",
  "user_doc_text": "Optional extra context pasted here",
  "top_k": 6
}
```

#### Multipart (optional PDF upload)

Form fields:

* `message` (string)
* `session_id` (optional)
* `user_pdf` (file, `.pdf`) **OR** `user_doc_text` (string)

Response:

```json
{
  "session_id": "abc123",
  "answer": "...",
  "citations": [
    { "filename": "case1.pdf", "page": 3, "score": 0.12 }
  ]
}
```

Notes:

* The agent is instructed to **retrieve evidence first** using `cases_retriever`
* User-provided PDFs are processed temporarily and are **not persisted**

---

## Data storage

* SQLite DB (`DB_PATH`) stores:

  * `users` (email, password hash, role, optional location)
  * `chats` (client_id, lawyer_id, sender_id, message, created_at)
* Vector index (`INDEX_DIR`) stores embeddings + FAISS index for case PDFs


If you want, paste your `retrieval.py`, `processing.py`, and the actual folder layout you’re using, and I’ll tailor the README’s install commands, file names, and “Repo structure” section to match your repo exactly.

