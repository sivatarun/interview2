# Conversational Bot Design Guide
### General customer-service bot, with parallels to the Agenda Bot

> **Format note:** the diagrams are plain-text (ASCII) diagrams inside code blocks, so they survive import into Google Docs without needing a Mermaid renderer. Keep a monospace font (e.g. Courier New / Roboto Mono) on those blocks.
> Sources for every claim are in `citations.md` (topic numbers are shown in brackets, e.g. [T2]).

---

## 1. What a modern conversational bot is made of

| Layer | Customer-service bot | Agenda bot |
|---|---|---|
| Channel | Web widget, app, WhatsApp, email, voice | Web app chat, Slack/Teams |
| Pre-routing | Buttons, session state, rules (handoff, opt-out, PII) | Rules (cancel, restart, help) |
| Understanding | Intent router (embedding/ML → LLM fallback) or tool-calling agent | Extractor (LLM, structured output) against the template schema |
| State | Workflow + slots (order ID, reason) | Plan draft (candidates, sections, prep) |
| Knowledge | Help-centre RAG, order/billing APIs | Org directory, past meetings, notes (pgvector) |
| Actions (tools) | get_order, create_refund, handoff_to_human | suggest_candidates, propose_template, generate_section_prep |
| Memory | Conversation log, summary, user preferences, past tickets | Conversation log, summary, user's meeting preferences |
| Safety and quality | Guardrails, PII redaction, evals, human handoff | Permission-filtered org data, confirmation before sending invites, evals |

---

## 2. End-to-end architecture

```
 +-----------------------------------------------------------------------------------+
 |  CHANNELS:  Web chat | Mobile app | WhatsApp | Email | Voice (STT/TTS) | Slack     |
 +-------------------------------------+---------------------------------------------+
                                       | message + channel payload (buttons, IDs)
                                       v
 +-----------------------------------------------------------------------------------+
 |  API GATEWAY  (auth, rate limit, user identity)                                   |
 +-------------------------------------+---------------------------------------------+
                                       v
 +-----------------------------------------------------------------------------------+
 |  CONVERSATION SERVICE                                                             |
 |   1. lock conversation (Redis)      2. append message (Postgres)                  |
 |                                                                                   |
 |   +--------------+   +----------------+   +-----------------+   +-------------+  |
 |   | PRE-ROUTER   |-->| UNDERSTANDING  |-->| CONTEXT BUILDER |-->| AGENT (LLM) |  |
 |   | buttons,     |   | router and/or  |   | state + last N  |   | reply or    |  |
 |   | state, rules |   | extractor      |   | + summary +     |   | tool calls  |  |
 |   +--------------+   +----------------+   | retrieved facts |   +------+------+  |
 |                                            +-----------------+          |         |
 |   3. save reply + state   4. release lock   5. enqueue async jobs      |         |
 +----------------------------------------------------------------------|---------+
                                                                        | tool calls
                                       +--------------------------------+
                                       v
 +-----------------------------------------------------------------------------------+
 |  TOOL LAYER (function calling or MCP)                                             |
 |   Domain APIs        Knowledge (RAG)        Memory             Human handoff      |
 |   orders, billing    help centre / org      search_history     queue + summary   |
 |   (or plan service)  data via pgvector      get_preferences                       |
 +-----------------------------------------------------------------------------------+
                                       |
                                       v
 +-----------------------------------------------------------------------------------+
 |  DATA:  Postgres (conversations, messages, state_events, domain tables)           |
 |         pgvector (KB chunks, org data, conversation memory)                       |
 |         Redis (hot state, locks)    Warehouse (analytics, evals)                  |
 +-----------------------------------------------------------------------------------+

 ASYNC WORKERS: summary refresh | embeddings | long-term memory extraction | eval logging
```

---

## 3. Routing: does every message need an LLM? [T2, T3]

No. Use a **cascade**: cheap layers first, and the LLM only when they can't decide.

```
 user message
      |
      v
 [1] Channel payload?  (button / quick reply / deep link)  --yes--> known intent
      | no
      v
 [2] Active workflow expecting a slot?  ("order ID?")       --yes--> fill slot
      | no
      v
 [3] Rule match?  (agent/human, stop, profanity, PII)       --yes--> fixed action
      | no
      v
 [4] Embedding / small-ML router, confidence >= threshold?  --yes--> route
      | no
      v
 [5] LLM router / classifier (with conversation context)    -------> route / clarify
      |
      v
 [6] Alternative: one agent with tools, where the tool it picks IS the route
```

| Layer | Handles | Typical latency |
|---|---|---|
| 1. Channel payload | Buttons, menus, deep links | ~0 ms |
| 2. Session state | Answers to the question the bot just asked | ~0 ms |
| 3. Rules | Handoff, opt-out, safety, PII | <1 ms |
| 4. Embedding / small ML | Stable, common intents | ~5–50 ms |
| 5. LLM router | Ambiguous, multi-intent, context-dependent | ~0.5–3 s |
| 6. Tool-calling agent | Routing folded into the main LLM call | Inside the main call |

**Embedding router (how it works):** embed 5–50 example phrases per route, embed the user's message, pick the nearest route, and fall back if its score is below a threshold (e.g. 0.82).

**Small ML / embedding vs LLM router**

| | Small ML / embedding | LLM |
|---|---|---|
| Cost / latency | ~0, ms | Tokens, seconds |
| Context | Current message only | Whole conversation |
| Multi-intent, negation | Weak | Strong |
| Determinism | High | Lower |
| Best for | High-volume stable intents, voice | Ambiguous text, choosing agents or tools |

**Agenda-bot parallel:** the extractor *is* the router. One structured-output call returns field updates, questions and any change of intent. Rules sit in front only for "cancel" or "start over".

**How to decide:** can the UI capture the intent? Is the intent set small and stable? Is a workflow already active? What does a wrong route cost? What latency can the channel tolerate? How many handlers are there? Always add an out-of-scope path.

---

## 4. Tool-calling agents, handoffs, agents-as-tools [T3, T9]

```
 user msg --> LLM (history + tool schemas)
                 |
                 +-- text reply --------------------------> user
                 |
                 +-- tool_call(create_refund, {order_id})
                          |
                          v
                     your code runs it (validation, permissions)
                          |
                          v
                     result --> LLM --> reply --> user
```

| Term | Meaning | Who keeps control |
|---|---|---|
| Tool | A function the LLM can call | Main agent |
| Agent as tool | A tool implemented by a sub-agent | Main agent (gets the result back) |
| Handoff | Transfer of control to another agent | The other agent |

- **Pros:** no intent list to maintain, handles several intents in one message, uses the full conversation.
- **Cons:** costs an LLM call per turn, accuracy depends on tool names and descriptions, and gets worse once there are more than ~20–30 tools.
- **Rule:** put business checks *inside* tools (refund limits, permissions). Don't rely on the prompt for them.

---

## 5. Session state: short-term and long-term [T2, T4, T8]

Session state is needed **whatever router you use**. Every layer reads it.

```
 SHORT-TERM (one conversation)                 LONG-TERM (across conversations)
 +--------------------------------+            +----------------------------------+
 | conversations (1 row / convo)  |            | user_profile   (system of record)|
 |   state JSON  <- snapshot      |            | user_memory    (semantic, update)|
 |   summary                      |            | episodes       (episodic, append)|
 | messages (1 row / message)     |            | open_items     (tickets, promises)|
 |   append-only log              |            |  + embeddings for search         |
 | state_events (field changes)   |            +----------------------------------+
 +--------------------------------+
```

**Short-term state (customer service)**
```jsonc
{
  "conversation_id": "c_789", "user_id": "u_123", "channel": "whatsapp",
  "status": "active",
  "auth": {"level": "otp_verified"},
  "routing": {"current_intent": "refund_request", "confidence": 0.91, "router": "embedding"},
  "workflow": {"name": "refund_v2", "step": "collect_reason",
               "slots": {"order_id": "123", "reason": null}, "required_missing": ["reason"]},
  "entities": [{"type": "order", "id": "123", "first_seq": 2}],
  "pending_questions": [],
  "handoff": {"requested": false},
  "flags": {"sentiment": "frustrated"},
  "version": 17
}
```

**Agenda-bot equivalent:** `workflow.slots` becomes the plan draft (stored in the plan tables, because screens use it). The conversation state keeps the stage, fields that are inferred but not yet confirmed, entities, pending questions and notes.

**Long-term memory**

| Type | Example | Behaviour |
|---|---|---|
| Profile | Tier, language, plan | Read from systems of record |
| Semantic memory | "Prefers WhatsApp", "Likes 30-min meetings" | Updated or overwritten; has source, confidence and expiry |
| Episodic memory | "Late delivery on order 98, given credit" | Append-only summaries of past conversations |
| Open items | Pending refund, promised callback | Commitments the bot must remember |

**Where to store it**

| Option | Use |
|---|---|
| Redis | Hot state, locks, TTL |
| Postgres | Source of truth, audit, analytics |
| Framework stores | Rasa tracker store, LangGraph checkpointer |
| Vector index | Semantic search over memory and history (not the current workflow state) |

---

## 6. Context engineering: what to send to the model [T4, T5, T7, T8]

**Principle:** store everything, but send only what the next decision needs.

```
 +------------------- PROMPT (built fresh every turn) -------------------+
 | 1. System prompt + policies                     (fixed, cached)       |
 | 2. Structured state summary                     (~100-300 tokens)     |
 | 3. Relevant long-term facts (top-k)             (~200-500)            |
 | 4. Running summary of older turns               (~200-500)            |
 | 5. Retrieved snippets / tool results            (current turn only)   |
 | 6. Last N turns verbatim                        (N ~ 4-10)            |
 | 7. User message                                 (always last)         |
 +-----------------------------------------------------------------------+
   Important items at the START and END: models miss facts in the middle.
```

### Who decides what goes in

```
 DEVELOPER (design time)          CODE (runtime)              MODEL (runtime)
 context contract per intent  --> context builder loads   --> calls tools for
 or per template/schema           state, last N, summary,     anything missing
                                  pre-fetches retrieval       (pull)
                                  (push)
                     ^                                            |
                     +------ evals + logs reveal gaps <-----------+
```

| Approach | Effort | Control | Cost | Fit |
|---|---|---|---|---|
| Contracts + code (push) | Medium | High | Low | Regulated flows, voice |
| + Retrieval over history | Medium | Medium–high | Low–medium | Long or returning users |
| Model fetches via tools (pull) | Low | Lower | Higher | Open-ended agents |
| **Hybrid (recommended)** | — | — | — | Most bots |

**Context contract example (customer service)**
```yaml
refund_request:
  state: [workflow.slots, auth.level]
  live_data: [get_order(order_id), get_payment(order_id)]
  memory: {types: [constraint, open_items]}
  history: {last_n_turns: 6, include_summary: true}
  policies: [refund_policy_v3]
  tools: [create_refund, handoff_to_human]
```
**Agenda-bot parallel:** the template schema is the contract. There's one per template type, not one per intent.

### Choosing N and recovering older details

Don't rely on N to remember things. Use layers:

| Layer | Catches | Stored in |
|---|---|---|
| Structured state / draft | Field-like facts | `conversations.state` / domain tables |
| Evidence per field | Why a value was set | `state.<field>.evidence` |
| Entity index | People, orders, projects mentioned | `state.entities` |
| Pending questions | Unanswered asks | `state.pending_questions` |
| Running summary | Gist of old turns | `conversations.summary` |
| History search tool | Exact old wording | `messages` + embeddings |

Start with N = 6. Test "call-back" scenarios (turn 15 refers to turn 2). Fix extraction first; increase N last.

### Summary refresh (you implement it)
```
 after reply sent (async):
   if unsummarised_turns >= K (e.g. 8) or tokens > THRESHOLD (e.g. 3000):
       new_summary = cheap_llm(old_summary + turns older than last N)
       save summary, summary_upto_seq
```
For short conversations (like most agenda chats) you may not need it.

---

## 7. Messages that do several things at once [T7, T8]

Example: "Cancel order 12, update my email, and when will my refund arrive?"

The extractor returns a **list**, not a single intent:

```jsonc
{
  "actions":   [{"type": "cancel_order", "order_id": "12"},
                {"type": "update_email", "value": null}],      // missing value -> ask
  "questions": ["when will my refund arrive?"],
  "entities":  [{"type": "order", "id": "12"}],
  "intent_shift": null
}
```

1. Carry out what you can, then answer every question in one reply.
2. Queue anything you can't handle yet in `pending_questions`.
3. Validate conflicts in code.
4. Agents do this naturally with several tool calls.

**Agenda parallel:** "Make it 45 min, add Priya, and should I add a demo?" becomes two field updates plus one question.

---

## 8. Storage: tables and the vector index [T7, T8, T9]

```
 conversations (1 row/convo, updated)  ----<  messages (append-only)  ----o  message_embeddings
        |                                           |
        +----< state_events (field changes, audit)  |
        |
        +---- links to DOMAIN tables (orders/tickets  |  agenda_plans, sections...)

 Knowledge (separate, read via tools):  kb_chunks / people / meetings / meeting_chunks (+ embedding)
```

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE conversations (
  conversation_id UUID PRIMARY KEY, user_id TEXT NOT NULL,
  bot_type TEXT, status TEXT,
  domain_ref TEXT,                    -- ticket_id / plan_id
  state JSONB, state_version INT DEFAULT 0,
  summary TEXT, summary_upto_seq INT,
  created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ);

CREATE TABLE messages (
  conversation_id UUID REFERENCES conversations, seq INT,
  role TEXT, content TEXT, content_redacted TEXT,
  tool_name TEXT, tool_args JSONB, tool_result JSONB,
  extracted JSONB, model TEXT,
  prompt_tokens INT, completion_tokens INT, latency_ms INT,
  created_at TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, seq));

CREATE TABLE state_events (
  conversation_id UUID, seq INT, field TEXT,
  old_value JSONB, new_value JSONB, status TEXT, created_at TIMESTAMPTZ);

CREATE TABLE message_embeddings (
  conversation_id UUID, seq INT, user_id TEXT, chunk_text TEXT,
  embedding VECTOR(1536), model TEXT, created_at TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, seq));
CREATE INDEX ON message_embeddings USING hnsw (embedding vector_cosine_ops);

-- Knowledge base (customer service)          -- Org knowledge (agenda bot)
-- kb_chunks(doc_id, chunk_no, text, embedding)  people, meetings, meeting_chunks(+embedding)
```

**The two uses of pgvector**

| | Conversation memory | Knowledge (KB / org data) |
|---|---|---|
| Embeds | The bot's own messages and memories | Help articles, or people, past meetings and notes |
| Written by | The bot | A data pipeline |
| Used through | Pre-fetch / `search_history` | RAG tools (`search_kb`, `get_past_meetings`) |

**Practices:**
- Postgres is the source of truth; vectors are an index. Embed asynchronously, and store the embedding model name with each vector.
- Use hybrid search (keyword plus vector) for names and IDs.
- Move to a dedicated vector DB only at large scale.
- Partition messages by conversation and time.
- Redact PII on write, and set retention periods.

---

## 9. One message from start to finish

```
 User        Conv Svc       Pre-router   Extractor/Router   Domain API   Ctx Builder   Agent LLM    Async
  |  msg  ------>|               |               |              |             |            |          |
  |              |-- lock, save  |               |              |             |            |          |
  |              |-------------->| rules ok      |              |             |            |          |
  |              |------------------------------>| intents,     |             |            |          |
  |              |                               | updates      |             |            |          |
  |              |---------------------------------------------->| validate &  |            |          |
  |              |                                               | apply       |            |          |
  |              |------------------------------------------------------------>| build      |          |
  |              |                                                             |----------->| tools?   |
  |              |                                               |<--------------------------| call     |
  |              |                                               |-------------------------->| result   |
  |              |<---------------------------------------------------------------------------| reply   |
  |              |-- save reply + state, unlock                                                          |
  |<---- reply --|------------------------------------------------------------------------------------->| summary,
  |              |                                                                                       | embeddings,
  |              |                                                                                       | memory
```

---

## 10. Moving from screens to conversation (Agenda bot specifics)

```
   Screen 1 (candidates)   Screen 2 (template)   Screen 3 (prep)        Chat UI
            \                      |                   /                   |
             \                     |                  /                    |
              v                    v                 v                     v
          +-----------------------------------------------+     +-------------------+
          |           AGENDA PLAN SERVICE (source of truth) |<--- | Conversation Svc  |
          |  plan_candidates | plan_sections | section_prep |tools| + agent           |
          +-----------------------------------------------+     +-------------------+
                               | plan.updated events
                               v
                 open screens refresh + chat sees new version
```

**Stages in the conversation:**
```
 Intake --> S1 Candidates --> S2 Template & timings --> S3 Section prep --> Review --> Finalized
              ^                     ^                         ^              |
              +---------------------+-------------------------+--------------+  (edit any stage)
 Changing an upstream stage marks later stages "stale"; the bot offers to regenerate them.
 User-edited content is never overwritten unless the user asks.
```

**Rule:** if a screen needs the data, it lives in the domain tables. `conversations.state` holds only chat-specific data (stage, inferred-vs-confirmed fields, entities, pending questions, notes, last-seen plan version).

Full details are in `implementation.md`.

---

## 11. Quality, safety and operations

| Area | Practice |
|---|---|
| Evals | Simulated-user scenarios (vague user, everything at once, changes mind, call-backs); measure task completion, turns, accuracy, handoff rate |
| Observability | Log the exact context, tool calls, latency and tokens for each turn |
| Guardrails | Input/output filters, prompt-injection defences, grounding checks |
| Permissions | Enforced inside tools, never by the LLM |
| Human handoff | Explicit path, with a summary for the human agent |
| Cost | Small models for routing, extraction and summaries; prompt caching |
| Privacy | PII redaction, retention, user memory controls (view, delete, opt out) |

---

## 12. Further reading (full list in `citations.md`)

- Anthropic: *Building effective agents*; *Effective context engineering for AI agents*
- Airbnb: *Task-Oriented Conversational AI in Customer Support*; *Automation Platform v2*
- LinkedIn: *Musings on building a Generative AI product*
- Rasa: CALM flows, command generator, tracker stores
- Google: Dialogflow CX form parameters
- OpenAI: Structured Outputs; Agents SDK handoffs
- Liu et al.: *Lost in the Middle*; Packer et al.: *MemGPT*
- Discord: *How Discord stores trillions of messages*; pgvector

---

## 13. Open-source stack per layer (summary)

Full rationale and implementation sketches are in `implementation.md`, section 12.

| Layer | Pick | Why |
|---|---|---|
| Orchestration / state machine | LangGraph (MIT) | Graph + typed state, Postgres checkpointer, human-in-the-loop interrupts, any model |
| Extraction | Pydantic + vLLM guided JSON (or Instructor) | Typed, validated output; supports multi-intent lists |
| Routing | Rules + semantic-router (MIT), LLM fallback | Cheap cascade |
| LLM | Qwen3 Apache-2.0 checkpoints (or gpt-oss, Mistral Apache models) | Open weights under OSI licences, good tool calling |
| Serving / gateway | vLLM (Apache 2.0) + LiteLLM (MIT core) | OpenAI-compatible, high throughput, routing between small and large models |
| Embeddings / rerank | BGE-M3, bge-reranker via TEI | Multilingual, permissive licences |
| Storage / vectors | PostgreSQL + pgvector | One DB for state, messages, domain data and vectors |
| Cache / locks | Valkey (BSD) | Redis-compatible without AGPL/SSPL |
| Events / jobs | NATS, Celery (Temporal for durable workflows) | Lightweight and mature |
| Safety | Presidio, NeMo Guardrails, Guardrails AI | PII, topic rails, output validation |
| Observability / evals | Langfuse (MIT core), OpenTelemetry, promptfoo, DeepEval, Ragas | Self-hosted traces; CI eval gates |
| Human handoff (customer service) | Chatwoot (MIT core) | Open-source agent inbox |
| Voice (customer service) | faster-whisper, Piper, LiveKit Agents / Pipecat | Open-source real-time voice |

**Why not Rasa as the core?** Rasa's LLM engine (CALM) is in Rasa Pro, which needs a licence key, and Rasa Open Source is reportedly in maintenance mode. Rasa OSS can still serve as a classic intent classifier for high-volume, stable-intent customer-service bots.
**Not OSI open source:** Llama (Meta community licence) and Arize Phoenix (Elastic licence 2.0). Avoid them if you strictly need OSI open source.
