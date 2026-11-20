# Conversational Bot Design Guide
### A generic guide to designing conversational bots and agents

> **Scope:** this guide is generic. It applies to any conversational bot, and uses a customer-service bot as the running example. Short **"Compare: agenda bot"** notes show how the same idea plays out in a different kind of bot (a multi-part, form-like task) to make the differences clearer. Everything specific to the agenda bot lives in `implementation.md` and `hld_agenda_bot.md`.

> **Format note:** the diagrams are plain-text (ASCII) diagrams inside code blocks, so they survive import into Google Docs without needing a Mermaid renderer. Keep a monospace font (e.g. Courier New / Roboto Mono) on those blocks.
> Sources for every claim are in `citations.md` (topic numbers are shown in brackets, e.g. [T2]).

---

## 1. What a modern conversational bot is made of

| Layer | Customer-service bot (running example) | Compare: agenda bot |
|---|---|---|
| Channel | Web widget, app, WhatsApp, email, voice | Web app chat, Slack/Teams |
| Pre-routing | Buttons, session state, rules (handoff, opt-out, PII) | Rules (cancel, restart, help) |
| Understanding | Intent router (embedding/ML → LLM fallback) or tool-calling agent | Extractor (LLM, structured output) against the template schema |
| State | Workflow + slots (order ID, reason) | Plan draft (candidates, sections, prep) |
| Knowledge | Help-centre RAG, order/billing APIs | Org directory, past meetings, notes (OpenSearch) |
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
 |         Search index (knowledge base: pgvector or OpenSearch)                     |
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

**Compare: agenda bot.** There, the extractor *is* the router. One structured-output call returns field updates, questions and any change of intent. Rules sit in front only for "cancel" or "start over".

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

**Compare: agenda bot.** `workflow.slots` becomes a multi-part plan draft stored in domain tables, and there is no single active workflow step: the bot tracks a status per part instead (see section 7a).

**Long-term memory**

| Type | Example | Behaviour |
|---|---|---|
| Profile | Tier, language, plan | Read from systems of record |
| Semantic memory | "Prefers WhatsApp", "Prefers email receipts" | Updated or overwritten; has source, confidence and expiry |
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
**Compare: agenda bot.** The template schema is the contract. There's one per template type, not one per intent.

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
For short, single-task conversations you may not need it.

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

**Compare: agenda bot.** "Make it 45 min, add Priya, and should I add a demo?" becomes two field updates plus one question.

---

## 7a. Fixed order or user-led? Choosing the flow style

A general bot can mix two styles. Pick one **per task**, not for the whole bot:

| Style | What it means | Use when | Customer-service example | Compare: agenda bot |
|---|---|---|---|---|
| **Directed (fixed order)** | The bot leads through steps in a set order | Order is required by rules or by a system, e.g. you must verify identity before a refund | Refund: verify identity → pick order → reason → confirm | Not used |
| **Mixed-initiative (user-led, prerequisite-driven)** | The user picks what to talk about; the bot checks only what *that* needs, asks once if it can't guess, otherwise assumes and says so | The task has several parts the user may want in any order | Moving between "track order", "change address", "FAQ" within one chat | Attendees, structure and prep in any order |

**How to implement both in one bot:**
- **Across tasks:** always user-led. The router picks the task the message is about.
- **Within a task:** declare each step's prerequisites. A truly sequential workflow is just one where every step depends on the previous one. A user-led one has few or no dependencies between steps.
- Either way the same code applies: a prerequisite check, then ask, assume or proceed. Only the dependency map differs.

**Pattern:** mixed-initiative dialogue (either side can lead) vs directed dialog (the system leads). Sources are in `citations.md` Topic 11.

---

## 7b. Standing instructions: how an assistant "remembers" what the user asked once

**The question:** a user says something once, e.g. "whenever the design changes, update the implementation doc too". No template or intent list covers it, yet the assistant follows it on every later message. How?

### How an LLM assistant like Claude does it (in this very thread)

| Mechanism | What actually happens |
|---|---|
| **No templates, no intent list** | There's no classifier deciding "this is an update-docs intent". The model reads the message and works out what's wanted, because instruction-following is part of how the model was trained. |
| **The whole conversation is in the prompt** | On every turn the full history (up to the context-window limit) is sent to the model again. The old instruction is simply *still in the prompt*, so the model takes it into account when writing the next reply. Nothing is "checked against a table". |
| **Actions happen through tools** | Writing or editing files happens through **tool calls** (write file, edit file, run command). The model decides which tool to call and with what arguments; the host app runs it. This is the "tool-calling agent" pattern from section 4. |
| **Long chats get compacted** | When the history gets too long it's summarised. A one-off instruction can then get lost unless the summary keeps it. |
| **Persistent memory (when used)** | For instructions that must survive across sessions, the assistant writes them to **memory files**, a small long-term store that's loaded into the prompt at the start of each new session. In this thread, this instruction and the project context have now been saved that way. |

So there's no hidden table being checked on every message. It's **(1) the instruction staying in the context window**, **(2) the model's trained instruction-following**, and **(3) tools to carry out the action**. Optionally there's **(4) persistent memory**, so the instruction isn't lost after compaction or in a new session.

### Why your bot can't rely on the same trick

A production bot usually sends **only the last N turns plus a summary** (section 6), so an instruction from 30 turns ago would drop out of the prompt. The fix is to treat instructions like any other state: **extract them and store them explicitly**.

```
 user msg --> extractor detects a STANDING INSTRUCTION
              ("always...", "from now on...", "whenever X, do Y", "never...")
                   |
                   v
   save to state / memory as a structured rule  --> injected into EVERY prompt
   (scope: this conversation, or this user)          in a short "Rules from the user" block
```

**Schema (add to conversation state, or to `user_memory` with type `instruction`):**
```jsonc
"standing_instructions": [
  {"id": "si_1",
   "text": "Whenever the design changes, also update the implementation doc",
   "trigger": "design_change", "action": "update_doc:implementation",
   "scope": "conversation",          // conversation | user (persists across chats)
   "source_seq": 41, "created_at": "...", "active": true}
]
```

**Practices:**
- **Detect them with the extractor.** Add a `standing_instructions[]` field to its output schema. Phrases like "always", "from now on", "whenever", "never" and "every time" are strong signals.
- **Store them separately from chat history**, so they survive trimming and summarisation. This is the same reason facts go into state rather than being left in old messages.
- **Inject them into every prompt** as a short, high-priority block near the top. Keep it small.
- **Confirm once** ("Got it: I'll also update the implementation doc whenever the design changes"), and let the user list or remove them. ChatGPT memory works the same way, with memories the user can view and delete.
- **Scope them:** conversation-only vs user-wide (long-term memory).
- **Enforce critical ones in code** when the action is deterministic, e.g. a post-step hook that always runs `update_doc` after a design change. Don't rely only on the model remembering.

**Pattern:** *explicit memory for instructions* (semantic memory of type "instruction" or "preference") plus *context engineering*, so important rules are always in the prompt. Related: MemGPT and Mem0 long-term memory, ChatGPT memory, Anthropic's context-engineering guidance. Sources are in `citations.md` (Topics 4, 5 and 12).

---

## 7c. Building state when there's no single template (open-ended bots)

**The difference:** in a form-like bot (compare: agenda bot) one template defines every field, so extraction is easy: "fill these slots". A customer-service bot faces open-ended topics (refunds, delivery, account, billing, FAQs, complaints), often several in one chat. No single template fits. In practice, production bots **layer** state: a small fixed core, a generic "case" object, a schema per workflow loaded only when that workflow is active, and free-form facts and memory.

```
 +--------------------------------------------------------------------------+
 | L1  CORE (fixed for every chat)   user, auth, channel, language, status  |
 +--------------------------------------------------------------------------+
 | L2  CASES (generic, any topic)    a list of issues raised in this chat:  |
 |     {issue, category, entities, status, resolution, open_questions}      |
 +--------------------------------------------------------------------------+
 | L3  ACTIVE WORKFLOW SCHEMA        loaded only when a workflow starts,    |
 |     (one per task: refund,        e.g. refund needs order_id, reason,    |
 |      address change, booking)     amount. Same slot filling as a form bot|
 +--------------------------------------------------------------------------+
 | L4  FREE-FORM FACTS / MEMORY      LLM-extracted facts with no fixed      |
 |                                   schema: "has a newborn, prefers calls" |
 +--------------------------------------------------------------------------+
 | L5  SUMMARY + TOOL RESULTS LOG    running summary; results of tool calls |
 +--------------------------------------------------------------------------+
```

### How each layer is filled

| Layer | How it's extracted | Industry example |
|---|---|---|
| **L1 Core** | From the channel and auth system, no LLM | Every production bot |
| **L2 Cases** | Each turn the LLM returns `case_updates[]`: a new issue, a changed status, entities (order ID, product) | Ticket/case objects in helpdesk tools; LinkedIn and Airbnb route each request to a handler |
| **L3 Workflow schema** | The router picks the workflow, then its **schema is loaded at runtime** and slots are filled like a form. Schemas live in config, not code, so new ones need no retraining | **Google Schema-Guided Dialogue**: state tracking that works on *unseen* schemas given at runtime. **Dialogflow CX** forms, **Rasa** flows, **Intercom Fin Procedures** (written step-by-step logic per workflow type) |
| *L3 alternative* | **Tool arguments are the slots.** The agent fills `create_refund(order_id, reason)` from the conversation, and the tool's schema acts as the template | OpenAI Agents SDK and Anthropic tool-use patterns |
| **L4 Free-form facts** | The LLM extracts candidate facts, then decides **ADD / UPDATE / DELETE / NOOP** against existing memory | **Mem0** paper (2025); ChatGPT memory |
| **L5 Summary + tool log** | Running summary (async); every tool result is stored with its turn | Anthropic context engineering; MemGPT |
| *Pure-RAG answers* | For FAQ-style questions there's little state: the question, retrieved articles, an answer, and quality checks | **DoorDash** Dasher support: RAG, then an LLM guardrail, then an LLM judge |

### Generic state schema (customer service)

```jsonc
{
  "core":   {"user_id": "u_123", "auth": "otp_verified", "channel": "chat", "lang": "en"},
  "cases": [
    {"case_id": "k1", "issue": "late delivery", "category": "delivery",
     "entities": {"order_id": "123"}, "status": "resolved", "resolution": "₹100 credit"},
    {"case_id": "k2", "issue": "wants refund for damaged item", "category": "refund",
     "entities": {"order_id": "456"}, "status": "in_progress",
     "workflow": {"name": "refund_v2", "schema_version": 3,
                  "slots": {"order_id": "456", "reason": "damaged", "photo": null},
                  "required_missing": ["photo"]}}
  ],
  "active_case": "k2",
  "facts": [{"text": "prefers phone call over chat", "op": "ADD", "source_seq": 7}],
  "pending_questions": [],
  "standing_instructions": [],
  "summary": "Resolved late delivery for 123 with credit. Now refund for 456."
}
```

**Extractor output, per turn (no single template):**
```jsonc
{"case_updates": [{"case_id": "new", "issue": "...", "category": "...", "entities": {}}],
 "slot_updates": [{"case_id": "k2", "slot": "photo", "value": "uploaded"}],   // only if a workflow is active
 "facts": [{"op": "ADD|UPDATE|DELETE", "text": "..."}],
 "questions": ["..."], "standing_instructions": []}
```

### Form-like bot vs open-ended bot

| | Form-like (compare: agenda bot) | Open-ended (customer service) |
|---|---|---|
| Templates | **One** fixed schema | **Many** small schemas (one per workflow), loaded on demand, plus a generic case object |
| What extraction targets | Known fields | Cases + slots of the active workflow + free-form facts |
| Topic changes in one chat | Rare | Common, so keep a **list of cases** with an `active_case` |
| Where "done" is defined | All parts confirmed | Per case: resolved or escalated |
| Unknown topics | Out of scope | RAG answer, or hand off to a human |
| State size | Small, bounded | Grows. Close old cases, summarise, keep only the active case in full in the prompt |

**Practices for open-ended bots:**
- **Keep schemas as data** (YAML/JSON per workflow), versioned, so adding a workflow doesn't need a code change. This is the "schema-guided" idea.
- **Send only the active case in full.** Closed cases appear as one summary line.
- **Validate extracted slots against the workflow schema** (Pydantic) before acting.
- **Free-form facts need dedup and conflict handling** (Mem0-style ADD/UPDATE/DELETE), or memory fills with contradictions.
- **Test with simulated customers** across topic switches (Intercom Simulations, DoorDash's simulator).

Sources are in `citations.md` Topic 13.

---

## 8. Storage: tables and the vector index [T7, T8, T9]

```
 conversations (1 row/convo, updated)  ----<  messages (append-only)  ----o  message_embeddings
        |                                           |
        +----< state_events (field changes, audit)  |
        |
        +---- links to DOMAIN tables (orders, tickets, bookings ... the business data)

 Knowledge (separate, read-only, via tools):  kb_chunks (+ embedding) in pgvector or OpenSearch
```

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE conversations (
  conversation_id UUID PRIMARY KEY, user_id TEXT NOT NULL,
  bot_type TEXT, status TEXT,
  domain_ref TEXT,                    -- ticket_id / order_id / any business record
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

-- Knowledge base (read-only, filled by an ingestion pipeline)
-- kb_chunks(doc_id, chunk_no, text, embedding, acl)
-- Compare: agenda bot keeps its knowledge (people, meetings, notes) in OpenSearch instead
```

**The two uses of pgvector**

| | Conversation memory | Knowledge base |
|---|---|---|
| Embeds | The bot's own messages and memories | Help articles, policies, product docs |
| Written by | The bot | A data pipeline |
| Used through | Pre-fetch / `search_history` | RAG tools (`search_kb`) |

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

## 10. Adding conversation to an existing app with UI screens (forms)

Many bots are added to products that already have screens: a refund form, a booking wizard, a settings page. The general rule: **the chat and the screens are both clients of the same domain service**. The bot doesn't own the business data.

```
   Screen A          Screen B          Screen C               Chat UI
       \                |                 /                       |
        v               v                v                        v
     +------------------------------------------+   tools   +--------------------+
     |   DOMAIN SERVICE (source of truth)       |<----------| Conversation Svc   |
     |   validation, business rules, versions   |           | + agent            |
     +------------------------------------------+           +--------------------+
                         | "record.updated" events
                         v
         open screens refresh + chat sees the new version on its next turn
```

**Practices:**
- **The screens' APIs become the bot's tools.** Business rules then live in one place, not in prompts.
- **Store each screen's data separately**, so screens keep working and a user can start in chat and finish on a screen, or the other way round.
- **`conversations.state` holds only chat-specific data**: focus, pending questions, entities, inferred or assumed fields, last-seen record version. If a screen needs it, it belongs in the domain tables.
- **Optimistic concurrency** (a `version` field) and update events, so edits made on a screen and in chat don't overwrite each other.
- **Mark dependent data "needs update"** when something it depends on changes, and never overwrite user-edited values automatically.
- **Choose the flow style per task** (section 7a): screens that used to be a fixed wizard don't have to stay sequential in chat.

| | Customer-service example | Compare: agenda bot |
|---|---|---|
| Existing screens | Order details, refund form, address change | Attendee suggestions, meeting template, section prep |
| Domain service | Orders / Refunds service | Agenda Plan service |
| Flow style in chat | Refund stays directed (identity check first); other tasks user-led | All three parts user-led, in any order |

Agenda-bot details: `implementation.md` and `hld_agenda_bot.md`.

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
| *Managed alternative* | Amazon Bedrock (Claude, or open-weight models such as Qwen3 / gpt-oss) | No GPU servers to run; the model is a managed service rather than open source (compare: the agenda bot uses this) |
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
