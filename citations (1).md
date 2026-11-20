# Conversational AI: Citations and Notes

A running log of every source cited in this learning thread, with the main point taken from each.
Note: links marked *(secondary)* are third-party summaries or mirrors. Check the original before quoting numbers.

---

## Topic 1: How chatbots evolved and how they're built (overview, from memory and not yet verified)

| Source | Main point |
|---|---|
| Weizenbaum, ELIZA (1966) | The first pattern-matching chatbot. |
| Uber Eng: Plato Research Dialogue System (2019) | An open framework for modular dialogue systems (NLU → dialogue manager → NLG). |
| Uber Eng: COTA | ML that classifies and routes customer support tickets. |
| Google AI blog: Duplex (2018), Meena (2020), LaMDA (2021) | The move from task bots to large open-domain neural chat models. |
| Microsoft: XiaoIce paper (arXiv 1812.08989), DialoGPT | Social chatbot design; pretrained dialogue generation. |
| Meta: BlenderBot | An open-domain chatbot with memory and search. |
| Lewis et al. 2020: RAG; Yao et al. 2022: ReAct | Retrieval grounding; the reason-and-act loop that agents use. |
| Anthropic: Building effective agents (Dec 2024) | Workflows versus agents, and a catalogue of design patterns. |
| Salesforce Agentforce; MS AutoGen / Semantic Kernel; Google A2A / ADK; Uber Genie / QueryGPT | Platforms and agents from the current agentic era. |

---

## Topic 2: Does every message go to an LLM intent classifier? (routing layers)

**Main point:** No. Production systems use a cascade: channel payload/buttons → session state → rules → small ML or embedding router → LLM only for low-confidence cases. A further option is a single agent where tool calling does the routing.

| Source | Main point |
|---|---|
| [Anthropic: Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) | Routing is its own workflow pattern. The classifier can be an LLM *or* a traditional model. Examples: support queries split into general/refund/tech; easy queries sent to a cheaper model. |
| [Airbnb: Discovering & Classifying In-app Message Intent](https://medium.com/airbnb-engineering/discovering-and-classifying-in-app-message-intent-at-airbnb-6a55f5400a0c) | Uses a dedicated ML intent classifier on guest/host messages. |
| [Airbnb: Task-Oriented Conversational AI in Customer Support](https://medium.com/airbnb-engineering/task-oriented-conversational-ai-in-airbnb-customer-support-5ebf49169eaa) | Intent detection, then a workflow (Mutual Cancellation example). |
| [Airbnb: Intelligent Automation Platform](https://airbnb.tech/?p=40) | A generic platform that supports several conversational AI products. |
| [Airbnb IVR summary (ZenML)](https://www.zenml.io/llmops-database/ml-powered-interactive-voice-response-system-for-customer-support) *(secondary)* | ASR → an Issue Detection Service that runs intent models in parallel. |
| [Airbnb Automation Platform v2 summary](https://besthub.dev/articles/airbnb-automation-platform-v2-enabling-llm-driven-conversational-ai-3af1110468f3) *(secondary)* | v1 used predefined workflows; v2 is an LLM-native hybrid. |
| [LinkedIn: Musings on building a GenAI product (mirror)](https://gsmarenas.netlify.app/host-https-www.linkedin.com/blog/engineering/generative-ai/musings-on-building-a-generative-ai-product) *(secondary)* | A routing → retrieval → generation pipeline. The router picks a specialist agent and checks whether the query is in scope. |
| [The Decoder on LinkedIn](https://the-decoder.com/linkedin-shares-insights-into-the-challenges-of-putting-llms-to-work/) *(secondary)* | The simple pipeline was easy to build; getting quality up was the hard part. |
| [InfoQ: LinkedIn multi-agent](https://infoq.com/news/2025/09/linkedin-multi-agent) | Hiring Assistant moved to multi-agent orchestration on existing messaging infrastructure. |
| [vLLM Semantic Router](https://vllm.ai/blog/semantic-router) | Open source: a small model classifies a request before it is sent to an LLM. |
| [LLM classification & semantic routing patterns](https://alivedise.github.io/backend-engineering-essentials/ai-backend-patterns/llm-based-classification-and-semantic-routing) *(secondary)* | Embedding router takes ~5–10 ms; an LLM classifier call takes ~0.5–3 s. Recommends a rules → embedding → LLM cascade. |

---

## Topic 3: Embedding routers, session state, ML vs LLM routers, tool-calling as router

**Main points:**
- **Embedding router:** embed a few example utterances per route, then pick the nearest route by cosine similarity, subject to a threshold. If no route passes the threshold, fall back.
- **Session state:** has short-term (turn, active flow, slots) and long-term (profile, memory) parts. It lives in an in-memory cache (Redis), a SQL/NoSQL DB, or a framework checkpointer, with client-side tokens or IDs linking to it.
- **Small ML/embedding vs LLM router:** fast, cheap, deterministic and needs labelled data, versus flexible, context-aware and zero-shot but slow, costly and non-deterministic.
- **Tool-calling as router:** a single agent gets tool schemas or handoff tools, and the model's choice of tool is the routing decision.

| Source | Main point |
|---|---|
| [Aurelio Semantic Router: overview](https://docs.aurelio.ai/semantic-router/user-guide/concepts/overview.md) | Routes are defined by example utterances; the highest similarity above a threshold wins. |
| [Aurelio Semantic Router: routers (Semantic / Hybrid)](https://docs.aurelio.ai/semantic-router/user-guide/components/routers.md) | Dense-only, or hybrid dense + sparse (keyword) matching. Note that v0.x and v1 APIs differ. |
| [Rasa: Tracker stores](https://rasa.com/docs/rasa/tracker-stores/) | Dialogue state stored in InMemory (dev only), SQL (Postgres/Oracle/SQLite), Redis, Mongo or Dynamo stores; a Redis lock store is used for multiple replicas. |
| [LangGraph: checkpointers](https://docs.langchain.com/oss/python/integrations/checkpointers/index.md) | Per-thread state is persisted by Postgres, Redis or other checkpointers, which can be swapped without changing graph code. |
| [LangGraph: add memory](https://docs.langchain.com/oss/python/langgraph/add-memory.md) | Short-term memory comes from thread checkpoints; long-term memory comes from a store. |
| [LangChain blog: LangGraph v0.2](https://blog.langchain.dev/langgraph-v0-2) | Checkpointer libraries are interchangeable. |
| [OpenAI Agents SDK: handoffs (JS guide mirror)](https://proxy-dev.blitzz.co/proxy/123456/openai.github.io/openai-agents-js/guides/handoffs) *(secondary)* | Each handoff target is exposed to the model as a `transfer_to_<agent>` tool. |
| [Towards Data Science: Agents SDK multi-agent](https://towardsdatascience.com/hands-on-with-agents-sdk-multi-agent-collaboration/) *(secondary)* | Two patterns: handoffs and agents-as-tools. |
| [Towards AI: Route, call tools, hand off in support](https://pub.towardsai.net/ai-agent-orchestration-how-to-route-call-tools-and-hand-off-in-customer-support-6c2cfe280087) *(secondary)* | A support example combining routing, tools and handoff. |
| [Anthropic: Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) | Agents = an LLM using tools in a loop; tool design (the agent–computer interface) matters as much as prompts. |

---

## Topic 4: How much session state to send to the model; schemas for short-term and long-term state

**Main points:**
- Send the *minimum context that keeps the next decision correct*, assembled per turn instead of dumping everything.
- Budget tokens by slot (system prompt, state summary, last N turns, retrieved facts, tool results).
- Put the most important items at the start and end of the prompt.
- Summarise or compact older turns, and clear stale tool output.
- Store more than you send: the DB keeps everything, and the prompt gets a projection of it.
- Schema split: **short-term** (conversation, turns, workflow/slots, tool calls) and **long-term** (user profile, preferences, semantic facts, episodic summaries, open issues), each with source, confidence, TTL and consent.

| Source | Main point |
|---|---|
| [Anthropic: Effective context engineering for AI agents](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents) | Treat context as a finite attention budget. Techniques: compaction (summarise and restart), structured note-taking outside the context, clearing tool results, sub-agents, retrieving just in time. |
| [Context engineering: memory, compaction, tool clearing](https://tianpan.co/blog/2026-02-26-context-engineering-memory-compaction-tool-clearing) *(secondary)* | Clear tool results first; compact at about 70% of the window, not at the limit. |
| [Liu et al., Lost in the Middle (arXiv 2307.03172, TACL 2024)](https://arxiv.org/abs/2307.03172) | Accuracy is highest when key information is at the start or end of the context, and drops for information in the middle and for longer contexts. |
| [OpenAI: Memory and new controls for ChatGPT](https://openai.com/index/memory-and-new-controls-for-chatgpt/) | Two memory types (explicit saved memories and chat-history reference), with user controls to view, delete or turn off, plus temporary chat. |
| [Mem0: How to create AI agents with long-term memory](https://mem0.ai/blog/how-to-create-ai-agents-with-long-term-memory) *(vendor)* | Memory at user, session and agent levels; extract facts, then add, update or delete them. |
| [Agent memory architectures glossary (Klu)](https://klu.ai/glossary/agent-memory-architectures) *(secondary)* | Semantic memory (facts that are updated and overwritten) vs episodic memory (time-ordered events, append-only). Agent-managed memory (MemGPT) vs pipeline-managed memory (Mem0). |
| [Mem0 benchmark: OpenAI Memory vs LangMem vs Letta vs Mem0](https://mem0.ai/blog/benchmarked-openai-memory-vs-langmem-vs-memgpt-vs-mem0-for-long-term-memory-here-s-how-they-stacked-up) *(vendor benchmark)* | A comparison of memory systems; the claims need independent checking. |
| [LangGraph: add memory](https://docs.langchain.com/oss/python/langgraph/add-memory.md) | Thread checkpoints for short-term memory, a separate namespaced store for long-term memory. |

---

## Topic 5: Who decides what context the next turn needs? Finding the useful parts of older messages

**Main points:** It's a shared job, split into layers.
1. **The developer, at design time:** context contracts per intent or workflow (which state slices, tools and policies each flow needs).
2. **Deterministic code at runtime:** loads those slices based on the router's output and the workflow step.
3. **Retrieval over history and memory:** query rewriting plus semantic or hybrid search finds relevant older turns and episodes.
4. **The model itself:** fetches extra context on demand through tools or memory functions (MemGPT style; Anthropic's just-in-time retrieval).
5. **Evals and logs:** close the loop, so the developer refines the contracts over time.

The developer designs the *policy*, not every case.

| Source | Main point |
|---|---|
| [Anthropic: Effective context engineering](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents) | Keep lightweight references (IDs, paths) and let the agent load data just in time with tools; mix this with some data retrieved up front. |
| [Packer et al., MemGPT: Towards LLMs as Operating Systems (arXiv 2310.08560)](https://arxiv.org/abs/2310.08560) | The context window is treated like RAM, with external storage behind it; the LLM calls memory functions to page information in and out itself. |
| [MTRAG: Multi-turn conversational RAG benchmark (arXiv 2501.03468)](https://arxiv.org/abs/2501.03468) | Follow-up questions often can't stand on their own; rewriting the query before retrieval helps. |
| [Library of LLM Intrinsics for RAG (arXiv 2504.11704)](https://arxiv.org/abs/2504.11704) | A query-rewrite adapter turns the last utterance into a standalone query. |
| [RAGLight: query reformulation docs](https://raglight.mintlify.app/documentation/reformulation) *(secondary)* | Rewrite the follow-up into a self-contained query; skip this for first turns to save latency. |

---

## Topic 6: Meeting-agenda planner bot (template-driven slot filling)

**Main points:**
- For a template-driven bot, the **template schema is the context contract**: fields, required/optional, types, validation and dependencies.
- The developer owns the schema and its rules. The LLM extracts several fields from free text, asks for missing or ambiguous ones and confirms inferences.
- Context sent each turn = the schema + the current draft (filled, missing, inferred-but-unconfirmed fields) + the last few turns. The full history is rarely needed.
- Ways to cut the developer's load: generate the schema from the template, pick a template type that branches the schema, use the LLM to suggest values with confirmation, use structured outputs for extraction, and run evals on simulated users.

| Source | Main point |
|---|---|
| [Rasa: LLM Command Generator (CALM)](https://rasa.com/docs/pro/customize/command-generator) | The LLM turns user messages into commands (start flow, set slot, clarify, cancel); the developer-defined flow and slots stay in control. |
| [Rasa: Writing flows](https://rasa.com/docs/pro/build/writing-flows) | `collect` steps for slots; slots can be filled by the LLM (`from_llm`) at any turn. |
| [Rasa: Dialogue understanding](https://www.rasa.com/docs/learn/concepts/dialogue-understanding.md) | The prompt holds conversation history, the relevant flows (top matches only) and slots. |
| [Google Dialogflow CX: Parameters and forms](https://docs.cloud.google.com/dialogflow/cx/docs/concept/parameter) | Each page has a form of required and optional parameters; the agent prompts for required ones in order, with reprompts. Optional ones are filled only if the user offers them. |
| [OpenAI: Introducing Structured Outputs](https://openai.com/index/introducing-structured-outputs-in-the-api/) | `strict` JSON-schema outputs give reliable extraction straight into a schema. |
| [Microsoft Learn: Extract entities with structured outputs](https://learn.microsoft.com/azure/developer/ai/how-to/extract-entities-using-structured-outputs) | Azure OpenAI pattern for schema-based entity extraction. |

---

## Topic 7: The context builder, retrieval and model tools; multi-question turns; references to older details; storing messages

**Main points:**
- The **context builder** (deterministic code) is the orchestrator that runs every turn. **Retrieval** is a capability it can call *before* the LLM (pre-fetch). **Model tools** let the LLM call the same retrieval *during* its reasoning (on demand). Tools are one way to trigger retrieval; retrieval is optional for the builder.
- Multiple questions in one message: extract a list of intents or actions, answer each in one reply (or queue the ones you can't handle yet), and keep a `pending_questions` list in state.
- References to older details: N is a budget, not a fixed number (4–10 turns, ~1–3k tokens). Beyond N, rely on the draft or state, a running summary, entity indexes and history retrieval via a tool. Same approach for support bots.
- Store every message: a relational/document DB (Postgres) is the source of truth, append-only and partitioned by conversation. Embeddings are an optional *index* (pgvector or a vector DB), not the primary store.

| Source | Main point |
|---|---|
| [Discord: How Discord stores trillions of messages](https://discord.com/blog/how-discord-stores-trillions-of-messages) | Large-scale message stores are partitioned by channel/conversation and time bucket; Discord moved from MongoDB to Cassandra to ScyllaDB. |
| [ScyllaDB: Discord case study](https://resources.scylladb.com/blog/how-discord-stores-trillions-of-messages) *(secondary)* | Migration details; the cluster shrank from 177 to 72 nodes. |
| [Databricks: What is pgvector](https://databricks.com/blog/what-is-pgvector) | Vector search inside Postgres, next to the relational data. |
| [ClickHouse: Scaling vector search in Postgres](https://clickhouse.com/resources/engineering/scale-vector-search-postgres) *(vendor)* | pgvector is fine up to moderate scale; watch for memory, filtering recall and update bloat. Go hybrid or dedicated at very large scale. |
| [pgvector vs Pinecone 2026](https://www.kunalganglani.com/blog/pgvector-vs-pinecone.md) *(secondary)* | Start with pgvector; move to a dedicated vector DB for very low latency or very large scale. |
| [Anthropic: Effective context engineering](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents) | Pre-fetched vs just-in-time (tool) context; a hybrid of the two is recommended. |
| [MemGPT (arXiv 2310.08560)](https://arxiv.org/abs/2310.08560) | Recall storage = a searchable full message log the agent queries through functions. |

---

## Topic 8: Clarifications (what the context builder does, how lists get extracted, memory layers as state, summary refresh, vector index schema)

**Main points:**
- The context builder is code that assembles the **final prompt for the main LLM call**. Retrieval is one step it *may* run first; it doesn't build a prompt "for retrieval".
- Extracting several intents or fields in one message is done by an **LLM with structured output** (a list-typed schema). An embedding router can't do it on its own because it returns the single nearest route. A hybrid splits the message into clauses and routes each one, which is rarely worth it.
- Memory layers = fields inside the same `conversations.state` JSONB (draft + evidence + entities + pending questions), plus the `summary` column, plus the `messages` table. Not a separate DB.
- The summary refresh is code you write: a trigger (every K turns, or tokens > threshold), then an async LLM summarisation call, then an update to `summary` and `summary_upto_seq`. Some SDKs (Anthropic compaction, LangGraph/LangChain summarisation helpers) provide it.
- Vector index = a pgvector `vector` column (or a side table) in the same Postgres, with an HNSW index, filtered by user/conversation.

| Source | Main point |
|---|---|
| [pgvector (GitHub)](https://github.com/pgvector/pgvector) | The `vector(n)` type, HNSW/IVFFlat indexes, cosine distance operator `<=>`, and filtering with WHERE. |
| [Anthropic: Effective context engineering](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents) | Compaction = summarise when near the limit, then continue from the summary; structured note-taking outside the context. |
| [OpenAI: Structured Outputs](https://openai.com/index/introducing-structured-outputs-in-the-api/) | Schemas with arrays let one call return several intents, fields or questions. |
| [Databricks: What is pgvector](https://databricks.com/blog/what-is-pgvector) | Keep embeddings beside relational data; join and filter in one query. |

---

## Topic 9: Small LLM calls, the state row vs the messages table, the two uses of pgvector, "model tools" vs "agent as tool"

**Main points:**
- Small or cheap LLM calls do many jobs besides query rewriting: extraction, classification, summarisation, validation or judging, title and description generation.
- `conversations` = one row per conversation (latest state, updated in place with a version check). `messages` = one row per message (append-only). `state_events` = one row per field change.
- pgvector has two different uses: (a) **conversation memory** (embeddings of this bot's own messages), and (b) **org knowledge** (people, past meetings, documents), exposed to the agent as retrieval tools. The extension is the same; the tables and purposes differ. They can share one Postgres or be separate services.
- "Model tools" = any function the LLM can call (search, fetch, create). "Agent as a tool" = a tool whose implementation is another LLM agent. "Handoff" = transferring control to another agent.

| Source | Main point |
|---|---|
| [Anthropic: Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) | An augmented LLM = LLM + retrieval + tools + memory; the orchestrator-workers pattern (sub-agents). |
| [OpenAI Agents SDK: handoffs (mirror)](https://proxy-dev.blitzz.co/proxy/123456/openai.github.io/openai-agents-js/guides/handoffs) *(secondary)* | Handoffs vs agents-as-tools. |
| [Towards Data Science: Agents SDK multi-agent](https://towardsdatascience.com/hands-on-with-agents-sdk-multi-agent-collaboration/) *(secondary)* | Agent-as-tool returns its result to the caller, while a handoff passes control. |
| [Model Context Protocol](https://modelcontextprotocol.io) | Standard way to expose tools and data sources (e.g. an org-directory or meetings service) to any agent. |
| [pgvector (GitHub)](https://github.com/pgvector/pgvector) | One extension serves both memory and knowledge tables. |

---

## Reference: Schemas, tables and state structures used in this thread

> **Where these come from:** the *patterns* are standard industry practice and are backed by the sources above: per-conversation state (Rasa tracker store, LangGraph checkpointers), an append-only message log (Discord, MemGPT recall storage), slot/form schemas (Rasa CALM, Dialogflow CX), structured extraction (OpenAI Structured Outputs), semantic vs episodic memory (Mem0, MemGPT, ChatGPT memory), pgvector beside relational data (pgvector, Databricks), and summarisation/compaction (Anthropic). The **exact field names and tables below are my own reference design** combining those patterns, not copied from any single company. Adapt them to your needs.

### A. Comparison tables (the "this vs that" answers)

**A1. Routing layers (Topic 2)**
| Layer | What it handles | Typical cost |
|---|---|---|
| 1. Channel/client (structured input) | Buttons, quick replies, deep links, IVR digits | ~0 ms |
| 2. Session state rules | Active workflow / slot collection | ~0 ms |
| 3. Deterministic rules | Handoff keywords, opt-out, regex, safety, PII | <1 ms |
| 4. Small ML / embedding router | Stable, labelled intents | ~5–50 ms |
| 5. LLM classifier/router | Ambiguous, multi-intent, context-dependent | ~0.5–3 s + tokens |
| 6. Single agent, tool calling | The tool the model picks *is* the route | Inside the main call |

**A2. Small ML / embedding router vs LLM router (Topic 3)**
| | Small ML / embedding | LLM |
|---|---|---|
| Latency | ~5–50 ms | ~0.5–3 s |
| Cost | ~0 | Tokens on every call |
| Data needed | Labelled examples / a few utterances per route | Zero- or few-shot |
| Context awareness | Current message only | Full conversation |
| Multi-intent / negation | Weak | Strong |
| Determinism | High | Lower |
| Changing intents | Retrain / add examples | Edit the prompt |
| Best fit | High volume, stable intents, voice, first stage of a cascade | Ambiguous text, intents that change often, agent/tool selection |

**A3. Where to store session state (Topic 2b)**
| Option | Good for | Watch out for |
|---|---|---|
| In process memory | Local development | Lost on restart, single instance only |
| Redis (KV + TTL) | Hot per-turn state | Configure durability |
| Postgres / SQL | Durable state, audit, analytics | Slightly slower |
| NoSQL (Mongo/DynamoDB) | Flexible documents, scale | Data modelling |
| Framework stores (Rasa tracker, LangGraph checkpointer) | Built in | Framework lock-in |
| Client-side token / channel ID | Light context | Never trust it for sensitive data |
| Vector store | Long-term semantic memory | Not for the current workflow state |

**A4. Prompt token budget per turn (Topic 4)**
| Part | Contents | Budget |
|---|---|---|
| System + policies | Role, rules | Fixed (cache it) |
| State summary | Workflow, slots, auth, intent | ~100–300 |
| Long-term facts | Top-k relevant | ~200–500 |
| Recent turns | Last N word for word | 4–10 turns |
| Older-turn summary | Running summary | ~200–500 |
| Tool / RAG results | Current turn only, trimmed | What's left |
| User message | Always last | — |

**A5. Who decides the context (Topic 5)**
| Approach | Developer effort | Control | Cost | Fit |
|---|---|---|---|---|
| Developer contracts + code | Medium (per intent) | High | Low | Regulated flows, voice |
| + Retrieval over history | Medium (shared pipeline) | Medium–high | Low–medium | Long or returning users |
| Model fetches via tools | Low upfront | Lower | Higher | Open-ended agents |
| Hybrid | — | — | — | Most bots (recommended) |

**A6. Support bot vs agenda bot (Topic 7)**
| Support bot | Agenda bot |
|---|---|
| A contract per intent (20+) | One schema (per template type) |
| Retrieval over history for old facts | The draft holds the facts |
| Long, multi-topic conversations | Short, single-goal conversations |

**A7. Push (pre-fetch) vs pull (tool) retrieval (Topic 7)**
| | Push (code) | Pull (model tool) |
|---|---|---|
| Who decides | Developer rules | LLM at runtime |
| Latency | One LLM call | Two or more calls |
| Predictability | High | Lower |
| Handles the unexpected | Poorly | Well |

**A8. Memory layers for references to older details (Topics 7–8)**
| Layer | Catches | Stored in |
|---|---|---|
| Draft / structured state | Field-shaped facts | `conversations.state.draft` |
| Evidence per field | The *why* behind a value | `state.draft.<field>.evidence` |
| Entity index | People, projects, dates mentioned | `state.entities` |
| Pending questions | Unanswered asks | `state.pending_questions` |
| Notes | Nuances that aren't fields | `state.notes` |
| Running summary | Gist of turns older than N | `conversations.summary` |
| History search | Exact old wording | `messages` + `message_embeddings` |

**A9. Storage roles (Topic 7)**
| Role | Store |
|---|---|
| Source of truth (messages) | Postgres/MySQL; Cassandra/Scylla/DynamoDB at huge scale |
| Hot state | Redis (optional) |
| Semantic search | pgvector → dedicated vector DB at scale |
| Analytics | Warehouse through CDC/ETL |

**A10. The three core tables (Topic 9)**
| Table | Rows | Update style | Holds |
|---|---|---|---|
| `conversations` | 1 per conversation | Updated in place (versioned) | Latest state, summary, status |
| `messages` | 1 per message | Append-only | Raw + redacted text, tool calls, extracted info, metrics |
| `state_events` | 1 per field change | Append-only | Old → new value, cause |

**A11. Two uses of pgvector (Topic 9)**
| | Conversation memory | Org knowledge |
|---|---|---|
| Embeds | This bot's messages and memories | People, past meetings, notes, documents |
| Written by | The bot | A data pipeline |
| Used through | Pre-fetch / `search_history` | Tools: `find_person`, `get_past_meetings`, `search_meeting_notes` |
| Agenda bot needs it? | Rarely | Yes, the main value |

**A12. Tool vs agent-as-tool vs handoff (Topic 9)**
| Term | Meaning | Control |
|---|---|---|
| Tool | A function the LLM calls | Main agent keeps it |
| Agent as tool | A tool implemented by a sub-agent | Main agent keeps it; gets the result back |
| Handoff | Transfer to another agent | Moves to the other agent |

### B. JSON state structures

**B1. Short-term conversation state (support-bot flavour, Topic 4)**
```jsonc
{
  "conversation_id": "c_789", "user_id": "u_123", "channel": "whatsapp", "locale": "en-IN",
  "status": "active",                       // active | waiting_user | handed_off | closed
  "started_at": "...", "last_activity_at": "...",
  "auth": {"level": "otp_verified", "verified_at": "..."},
  "entry_context": {"page": "/orders/123", "campaign": null},
  "routing": {"current_intent": "refund_request", "confidence": 0.91,
              "router": "embedding", "intent_history": ["track_order", "refund_request"]},
  "workflow": {"name": "refund_v2", "step": "collect_reason",
               "slots": {"order_id": "123", "reason": null, "amount": 499},
               "required_missing": ["reason"], "retry_count": 1},
  "handoff": {"requested": false, "queue": null, "agent_id": null, "summary": null},
  "context_window": {"summary": "...", "summary_upto_turn": 14},
  "flags": {"sentiment": "frustrated", "escalation_risk": 0.6, "pii_detected": true},
  "version": 17
}
```

**B2. Turn record (Topic 4)**
```jsonc
{"conversation_id": "c_789", "turn_no": 15, "role": "user|assistant|tool|human_agent",
 "content": "...", "content_redacted": "...", "intent": "refund_request",
 "tool_call": {"name": "get_order", "args": {}, "result_ref": "s3://..."},
 "tokens": 42, "latency_ms": 820, "model": "...", "created_at": "..."}
```

**B3. Long-term memory (Topic 4)**
```jsonc
// user_profile (from systems of record; read-only for the bot)
{"user_id": "u_123", "name": "...", "tier": "gold", "language": "hi", "plan": "pro",
 "region": "IN", "consents": {"memory": true, "marketing": false}}
// user_memory (semantic; updated or overwritten)
{"memory_id": "m_1", "user_id": "u_123", "type": "preference|fact|constraint",
 "key": "contact_channel", "value": "prefers WhatsApp",
 "source_conversation_id": "c_456", "confidence": 0.8,
 "created_at": "...", "last_confirmed_at": "...", "expires_at": null, "embedding": []}
// episodes (episodic; append-only)
{"episode_id": "e_9", "user_id": "u_123", "conversation_id": "c_456",
 "summary": "...", "outcome": "resolved", "csat": 4, "intents": ["late_delivery"],
 "ended_at": "...", "embedding": []}
// open_items
{"user_id": "u_123", "type": "ticket", "ref": "T-5521", "status": "pending_refund", "promised_by": "..."}
```

**B4. Meeting-agenda template schema (Topic 6)**
```yaml
meeting_agenda:
  fields:
    title:            {type: string, required: true}
    meeting_type:     {type: enum, values: [kickoff, status, decision, brainstorm, 1on1, review], required: true}
    objective:        {type: string, required: true}
    desired_outcomes: {type: list, required: true, min: 1}
    date_time:        {type: datetime, required: false}
    duration_min:     {type: int, required: true, default_suggest: 30}
    attendees:        {type: "list[{name, role}]", required: false}
    decision_maker:   {type: string, required_if: "meeting_type == decision"}
    topics:           {type: "list[{title, owner, minutes}]", required: true, min: 1,
                       validate: "sum(minutes) <= duration_min"}
    pre_reads:        {type: list, required: false}
    template_sections: {type: multi_enum, values: [icebreaker, recap, discussion, decisions, action_items, aob]}
  completion: all_required_filled AND user_confirmed
```

**B5. Context contracts per intent (support, Topic 5)**
```yaml
refund_request:
  state: [workflow.slots, auth.level, routing.current_intent]
  live_data: [get_order(order_id), get_payment(order_id)]
  memory: {types: [constraint, open_items], filter: "related to orders"}
  history: {last_n_turns: 6, include_summary: true}
  policies: [refund_policy_v3]
  tools: [create_refund, handoff_to_human]
general_faq:
  history: {last_n_turns: 3}
  rag: {kb: help_center, top_k: 4}
  tools: [search_kb]
```

**B6. Per-turn context payload for the agenda bot (Topic 6)**
```jsonc
{"schema": "...meeting_agenda...",
 "draft": {"meeting_type": {"value": "kickoff", "status": "confirmed"},
           "objective": {"value": "align on Q1 scope", "status": "inferred"},
           "duration_min": {"value": 60, "status": "confirmed"},
           "topics": {"value": null, "status": "missing"}},
 "missing_required": ["topics", "desired_outcomes"],
 "last_turns": "...last 3–4 messages...",
 "user_prefs": {"default_duration": 30, "likes_icebreakers": false}}
```

**B7. Extraction output for multi-question messages (Topics 7–8)**
```jsonc
{"field_updates": [{"field": "duration_min", "op": "set", "value": 45},
                   {"field": "attendees", "op": "add", "value": "Priya"}],
 "questions": ["should I include a demo section?", "suggest an icebreaker"],
 "entities": [{"type": "person", "name": "Priya"}],
 "notes": [],
 "intent_shift": null}
```

**B8. Full agenda-bot `conversations.state` (Topic 8)**
```jsonc
{"template": "decision_meeting_v2",
 "draft": {
   "duration_min": {"value": 45, "status": "confirmed",
                    "evidence": [{"seq": 3, "quote": "keep it under an hour"}, {"seq": 9, "quote": "make it 45"}]},
   "objective": {"value": "get finance buy-in on Q1 budget", "status": "inferred",
                 "evidence": [{"seq": 2, "quote": "need finance on board"}]}},
 "entities": [{"type": "person", "name": "Priya", "role": "finance lead", "first_seq": 2, "last_seq": 9},
              {"type": "project", "name": "Q1 budget", "first_seq": 2}],
 "pending_questions": [{"seq": 9, "text": "suggest an icebreaker", "answered": false}],
 "notes": ["user worried about pushback from finance"]}
```

### C. SQL tables (Postgres + pgvector)

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE conversations (
  conversation_id  UUID PRIMARY KEY,
  user_id          TEXT NOT NULL,
  bot_type         TEXT,              -- agenda_planner | support
  status           TEXT,              -- active | completed | abandoned
  state            JSONB,             -- B1 / B8
  state_version    INT DEFAULT 0,
  summary          TEXT,
  summary_upto_seq INT,
  created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
);

CREATE TABLE messages (               -- append-only
  conversation_id  UUID REFERENCES conversations,
  seq              INT,
  role             TEXT,              -- user | assistant | tool | system
  content          TEXT,
  content_redacted TEXT,
  tool_name TEXT, tool_args JSONB, tool_result JSONB,
  extracted        JSONB,             -- B7 output for this turn
  model TEXT, prompt_tokens INT, completion_tokens INT, latency_ms INT,
  created_at       TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, seq)
);

CREATE TABLE state_events (           -- audit of field changes
  conversation_id UUID, seq INT, field TEXT,
  old_value JSONB, new_value JSONB, status TEXT,
  created_at TIMESTAMPTZ
);

CREATE TABLE message_embeddings (     -- conversation-memory index
  conversation_id UUID, seq INT,
  user_id TEXT NOT NULL,
  chunk_text TEXT,
  embedding VECTOR(1536),
  model TEXT,
  created_at TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, seq),
  FOREIGN KEY (conversation_id, seq) REFERENCES messages
);
CREATE INDEX ON message_embeddings USING hnsw (embedding vector_cosine_ops);
CREATE INDEX ON message_embeddings (user_id, conversation_id);

-- Long-term memory (B3) as tables: user_profile, user_memory (+ embedding), episodes (+ embedding), open_items
ALTER TABLE user_memory ADD COLUMN embedding VECTOR(1536);
CREATE INDEX ON user_memory USING hnsw (embedding vector_cosine_ops);

-- Org knowledge (Topic 9), exposed through tools
-- people(person_id, name, title, team, email, ...)
-- meetings(meeting_id, title, date, attendees[], decisions JSONB, action_items JSONB, ...)
-- meeting_chunks(meeting_id, chunk_no, text, embedding VECTOR(1536))

-- Semantic search query
SELECT m.seq, m.content_redacted, 1 - (e.embedding <=> :query_vec) AS score
FROM message_embeddings e JOIN messages m USING (conversation_id, seq)
WHERE e.user_id = :user_id AND e.conversation_id = :conv_id
ORDER BY e.embedding <=> :query_vec LIMIT 5;
```

### D. Code sketches

```python
# Context builder (Topic 8)
def build_context(conv, user_msg):
    state, recent, summary, extra = load_state(conv), load_last_n_messages(conv, 6), conv.summary, []
    if needs_retrieval(state, user_msg):
        extra = search_history(conv.user_id, rewrite_query(recent, user_msg))
    return render_prompt(system, schema, state, summary, extra, recent, user_msg)

# Summary refresh (Topic 8): run in the background after the reply
def maybe_refresh_summary(conv, K=8, THRESHOLD=3000, N=6):
    if count_after(conv.summary_upto_seq) >= K or tokens_after(conv.summary_upto_seq) > THRESHOLD:
        older = messages_between(conv.summary_upto_seq, latest_seq - N)
        save(conv, summary=llm_summarize(conv.summary, older), summary_upto_seq=latest_seq - N)

# Org-knowledge tools (Topic 9)
# find_person(name_or_role), get_past_meetings(attendees, topic),
# search_meeting_notes(query, user_id), get_open_action_items(people)
```

---

## Topic 10: Open-source stack choices and licences

**Main points:** for an OSS-only build use LangGraph (MIT) for orchestration, Pydantic + vLLM guided JSON for extraction, Qwen3 Apache-2.0 checkpoints on vLLM, Postgres + pgvector, Valkey (BSD) over Redis 8 (AGPL tri-licence), Langfuse (MIT core), Presidio and NeMo Guardrails for safety, and promptfoo / DeepEval / Ragas for evals. Rasa CALM is in Rasa Pro, which needs a licence key, so it isn't open source.

| Source | Main point |
|---|---|
| [Rasa forum: Announcing the Rasa Developer Edition](https://forum.rasa.com/t/announcing-the-rasa-developer-edition/61009) | Free Developer Edition of Rasa Pro (with CALM), with conversation limits. |
| [rasa-pro on PyPI](https://pypi.org/project/rasa-pro/3.10.21/) | Developer licence for exploration; a paid licence for larger production use. |
| [Voiceflow: Rasa chatbot overview](https://www.voiceflow.com/blog/rasa-chatbot) *(secondary)* | The free tier has been repackaged; open source is no longer the main line. |
| [Rasa forum: Open Source or Pro?](https://forum.rasa.com/t/rasa-open-source-or-rasa-pro-better-pricing-understanding/65291) | Community discussion of limits and pricing. |
| [InfoQ: Redis returns to AGPL](https://www.infoq.com/news/2025/05/redis-agpl-license) | Redis 8 adds AGPLv3 to RSAL/SSPL; Valkey stays BSD. |
| [Redis blog: What is Valkey](https://redis.io/blog/what-is-valkey/) | Background on the Linux Foundation fork. |
| [Langfuse: Open-source handbook](https://langfuse.com/handbook/chapters/open-source.md) | Core is MIT; enterprise features are in /ee. |
| [Langfuse: Self-hosting](https://langfuse.com/faq/all/self-hosting-langfuse.md) | Self-hosting is free on all tiers. |
| [TrueFoundry: LangGraph pricing](https://www.truefoundry.com/de/blog/langgraph-pricing) *(secondary)* | The LangGraph framework is MIT; LangGraph Platform is a separate paid product. |
| [VentureBeat: Qwen3 launch](https://venturebeat.com/ai/alibaba-launches-open-source-qwen3-model-that-surpasses-openai-o1-and-deepseek-r1) | Qwen3 open weights released under Apache 2.0. |
| [eWeek: Qwen3.8 licensing](https://www.eweek.com/news/alibaba-qwen3-8-27b-license-apac-china/) | Some newer flagship Qwen models use custom licences; check each checkpoint. |
| [Qwen3 agent review](https://www.kunalganglani.com/blog/qwen3-agent-capabilities-review.md) *(secondary)* | Possible mismatch between tool-call format and parser when serving with vLLM; test it. |
| [pgvector (GitHub)](https://github.com/pgvector/pgvector) | Vector search in Postgres. |
| [LangGraph checkpointers](https://docs.langchain.com/oss/python/integrations/checkpointers/index.md) | Postgres checkpointer for per-thread state. |
| [semantic-router docs](https://docs.aurelio.ai/semantic-router/user-guide/concepts/overview.md) | Embedding routing library. |

*Not yet verified this session (check the licence files on GitHub before adopting): vLLM, LiteLLM, TEI, BGE-M3, bge-reranker, Presidio, NeMo Guardrails, Guardrails AI, promptfoo, DeepEval, Ragas, NATS, Celery, Temporal, Chatwoot, faster-whisper, Piper, LiveKit Agents, Pipecat, Mem0, Letta, Unstructured, Qdrant, gpt-oss.*

---

## Topic 11: User-led conversation (mixed initiative) instead of a strict stage order

**Main points:** users don't think in stages. The bot treats the plan as parts (attendees, structure, prep) with **prerequisites, not a sequence**. Each message's focus is the part it's about; blocking prerequisites are asked once, others are assumed with defaults and shown. The bot only *suggests* unfinished parts. Staleness between parts is custom code (dependency tracking with invalidation).

| Source | Main point |
|---|---|
| [TITAN: Task-oriented Dialogues with Mixed-Initiative Interactions (IJCAI 2023)](https://www.ijcai.org/proceedings/2023/583) | Most task-oriented systems handle mixed initiative poorly; system-side initiative is needed to resolve situations efficiently. |
| [Ferguson & Allen, AAAI Fall Symposium 2005](https://www.cs.rochester.edu/~ferguson/papers/ferguson-allen-aaai-fall-2005.pdf) | Collaborative agents: user initiative = suggestions to the task manager; system initiative = goals the system pursues. |
| [MIMIC: mixed-initiative spoken dialogue (ANLP 2000, A00-1014)](https://preview.aclanthology.org/fix-sig-urls/A00-1014.pdf) | Separates task initiative from dialogue initiative and predicts who holds each turn by turn. |
| [Mixed-initiative in LLM conversational recommendation (arXiv 2403.17636)](https://arxiv.org/abs/2403.17636) | The user leads with new topics, requirements or negation; the system takes initiative by asking or recommending. |
| [US Patent 6246981: Natural language task-oriented dialog manager](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/6246981) | Mixed-initiative vs "directed dialog" (the system leads, the user answers briefly). |
| [Dialogflow CX: Transition route groups](https://docs.cloud.google.com/ruby/docs/reference/google-cloud-dialogflow-cx-v3/latest/Google-Cloud-Dialogflow-CX-V3-TransitionRouteGroup) | Reusable routes attached to pages or flows, evaluated after page routes, so a user can jump to other flows. |

---

## Topic 12: How assistants follow standing instructions (and how a bot should)

**Main points:** an LLM assistant has no template or intent table for "remember this rule". The instruction stays in the context window (the full history is resent each turn), the model follows it through trained instruction-following, and it acts through tool calls. Persistent memory files keep rules across sessions or compaction. A production bot that sends only the last N turns should extract standing instructions into explicit state or memory and inject them into every prompt.

| Source | Main point |
|---|---|
| [Anthropic: Effective context engineering](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents) | Compaction can drop details; structured note-taking and memory outside the context keep important state. |
| [OpenAI: Memory and new controls for ChatGPT](https://openai.com/index/memory-and-new-controls-for-chatgpt/) | Saved memories (explicit "remember this"), which users can view and delete, are injected into future chats. |
| [MemGPT (arXiv 2310.08560)](https://arxiv.org/abs/2310.08560) | The model writes important facts to persistent memory via functions, so they survive beyond the context window. |
| [Mem0: long-term memory for agents](https://mem0.ai/blog/how-to-create-ai-agents-with-long-term-memory) *(vendor)* | Extract, store and retrieve user-level memories (including preferences and instructions). |
| [Anthropic: Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) | Agents act through tools; the model chooses which tool to call. |

---

## Topic 13: State in open-ended bots (no single template)

**Main points:** customer-service bots layer their state: a fixed core, a generic list of cases (issues), a per-workflow schema loaded at runtime only when that workflow is active (schema-guided), free-form LLM-extracted facts with ADD/UPDATE/DELETE handling, plus a summary and a tool log. FAQ-style questions are answered with RAG plus guardrails and need little state. A form-like bot (agenda bot) has one fixed schema, which is much easier.

| Source | Main point |
|---|---|
| [Google Research: Introducing the Schema-Guided Dialogue Dataset (2019)](https://research.google/blog/introducing-the-schema-guided-dialogue-dataset-for-conversational-assistants/) | 18k dialogues, 17 domains; schemas are supplied at runtime, so state tracking works on unseen services zero-shot. |
| [Rastogi et al., Schema-Guided Dialogue (arXiv 1909.05855)](https://arxiv.org/abs/1909.05855) | The paper behind the dataset; one model handles many service schemas. |
| [SGD-X (arXiv 2110.06800)](https://arxiv.org/abs/2110.06800) | State trackers lose 12–18% accuracy when schemas are reworded, so test schema wording. |
| [DoorDash: Path to high-quality LLM-based Dasher support automation (2024)](https://careersatdoordash.com/?p=12568) | RAG support bot with an LLM guardrail (grounding, policy) and an LLM judge; reported ~90% fewer hallucinations. |
| [ZenML summary of DoorDash's system](https://www.zenml.io/llmops-database/rag-based-dasher-support-automation-with-llm-guardrails-and-quality-monitoring) *(secondary)* | Architecture summary; a failed guardrail triggers a retry or a human handoff. |
| [Intercom: Fin Procedures guide](https://fin.ai/learn/fin-procedures-guide) *(vendor)* | Natural-language, step-by-step procedures per workflow type; train, test, deploy, analyse loop. |
| [Intercom: Procedures and Simulations updates](https://intercom.com/blog/procedures-simulations-updates) *(vendor)* | An AI simulates customers to test procedures. |
| [ZenML: Intercom Fin from demo to production](https://www.zenml.io/llmops-database/scaling-an-autonomous-ai-customer-support-agent-from-demo-to-production) *(secondary)* | The biggest gains came from agent architecture, prompts, and custom RAG and ranking. |
| [Mem0 paper (arXiv 2504.19413)](https://arxiv.org/abs/2504.19413) | Extract facts, then the LLM chooses ADD / UPDATE / DELETE / NOOP against existing memories. |
| [Mem0 blog: token-efficient memory algorithm](https://mem0.ai/blog/mem0-the-token-efficient-memory-algorithm) *(vendor)* | A newer version moved to a single add-only extraction call. |

---

## Topic 14: Rerankers, relationship data, streaming on ECS Fargate

**Main points:** rerankers (cross-encoders) re-order a shortlist for text relevance, typically top 50 to top 10, adding about 100–200 ms. People ranking is better served by scoring on org signals. Org relationships at 1–2 hops are best pre-computed at ingestion; graph databases pay off at LinkedIn-like scale or for multi-hop queries. FastAPI SSE works on Fargate behind an ALB with a raised idle timeout and heartbeats, but Fargate has no GPUs for vLLM.

| Source | Main point |
|---|---|
| [Bi-encoders vs cross-encoders (ZeroEntropy)](https://zeroentropy.dev/articles/biencoder-vs-crossencoder) *(vendor)* | Bi-encoders for fast recall; cross-encoders are too costly for a whole corpus, so they're used on shortlists. |
| [The reranker gap in RAG pipelines](https://tianpan.co/blog/2026-04-20-reranker-gap-rag-pipelines) *(secondary)* | Retrieve 50–100, rerank to 5–10; reported accuracy gains; about 100–200 ms latency. |
| [LinkedIn: How LIquid connects everything](https://engineering.linkedin.com/blog/2023/how-liquid-connects-everything-so-our-members-can-do-anything) | LinkedIn's graph database (about 270B edges) powers People You May Know. |
| [InfoQ: LinkedIn recommendations on massive data](https://www.infoq.com/presentations/recommendation-massive-data) | People You May Know runs as candidate generation, then features, then scoring. |
| [Neo4j vs PostgreSQL for graph data](https://markaicode.com/vs/neo4j-vs-postgres/) *(secondary)* | Neo4j for variable-depth multi-entity traversal; Postgres is fine for shallow hierarchies. |
| [Recursive SQL guide (PuppyGraph)](https://www.puppygraph.com/blog/recursive-sql) *(vendor)* | Recursive CTEs handle org-chart hierarchies. |
| [AWS re:Post: ALB unexpected 504 timeouts](https://repost.aws/questions/QUXf7b9I0rQVSQzBoEqFBa1g/alb-unexpected-504-timeouts) | Send data within each idle-timeout window; TCP keep-alive alone doesn't count. |
| [SSE debugging with AWS Service Connect](https://www.oliverio.dev/blog/aws-service-connect-sse) *(secondary)* | FastAPI SSE on ECS broken by Service Connect, not by the ALB timeout. |
| [WebSocket.org: AWS ALB guide](https://websocket.org/guides/infrastructure/aws/alb/) *(secondary)* | ALB idle timeout default 60 s, max 4,000 s; keep heartbeats below the shortest timeout on the path. |

---

## Topic 15: Amazon Bedrock as the model layer

**Main points:** Bedrock offers managed Claude models (strong tool use and structured output) and open-weight models (Qwen3, gpt-oss). It removes GPU hosting, so the whole backend can run on Fargate. The trade-off is that the model is no longer open source. For Qwen3 on Bedrock, Converse-API tool use was reported as limited, so test it.

| Source | Main point |
|---|---|
| [AWS: Qwen models now available in Amazon Bedrock](https://aws.amazon.com/blogs/aws/qwen-models-are-now-available-in-amazon-bedrock) | Qwen3 is available as fully managed models. |
| [AWS: Bedrock adds 18 open-weight models (Dec 2025)](https://aws.amazon.com/about-aws/whats-new/2025/12/amazon-bedrock-fully-managed-open-weight-models) | gpt-oss, Qwen3-Next and others are managed on Bedrock. |
| [AWS ML blog: Qwen3 in Bedrock Marketplace](https://aws.amazon.com/blogs/machine-learning/qwen3-family-of-reasoning-models-now-available-in-amazon-bedrock-marketplace-and-amazon-sagemaker-jumpstart/) | Reports that the Converse API didn't support tool use for Qwen3 at the time; suggests InvokeModel. |
| [Bedrock: API compatibility by model](https://docs.aws.amazon.com/bedrock/latest/userguide/models-api-compatibility.html) | Which models support Converse, InvokeModel and Chat Completions. |
| [Bedrock: OpenAI models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-openai.html) | gpt-oss through Chat Completions and Converse. |
