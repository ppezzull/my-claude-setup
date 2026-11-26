# Ricerca: best practice per il CLAUDE.md globale (2026-11-26)

Deliverable: la riscrittura di `~/.claude/CLAUDE.md`. Questo file è il verbale:
cosa dicevano le fonti, cosa è cambiato, cosa resta aperto.

## Risposte in breve

1. **Brevità.** La documentazione ufficiale fissa il target sotto le 200 righe
   per file: "Longer files consume more context and reduce adherence". I file
   si concatenano, non si sovrascrivono, e due regole in conflitto vengono
   risolte a caso: "Claude may pick one arbitrarily".
2. **Non è un meccanismo di enforcement.** "Claude treats CLAUDE.md files and
   auto memory as context. They aren't enforced configuration." Ciò che deve
   essere bloccato va in hook o permessi.
3. **Costo certo, beneficio dipendente.**studio ETH su file di contesto a
   livello di repo: nessun miglioramento del tasso di successo, "+over 20%"
   di costo di inferenza. Un secondo studio su 10 repo e 124 PR trova runtime
   −28,64% e token in output −16,58% a parità di completamento. La differenza
   passa per il contenuto: regole puntuali che cambiano il comportamento,
   non panoramiche del repo.
4. **Contenuto procedurale o raro va nelle skill.** "For task-specific
   instructions that don't need to be in context all the time, use skills".
5. **Subagenti.** Vanno usati quando l'output è voluminoso e serve solo la
   sintesi; vanno evitati quando serve iterazione, contesto condiviso o
   latenza bassa. Costo: "agents typically use about 4× more tokens than chat
   interactions, and multi-agent systems use about 15×". Il brief deve dare
   "an objective, an output format, guidance on the tools and sources to use,
   and clear task boundaries". "Most coding tasks involve fewer truly
   parallelizable tasks than research".
6. **Orchestratore.** Schema orchestrator-workers ufficiale: un agente centrale
   scompone, delega e sintetizza. Cognition aggiunge due vincoli da fallimenti
   reali: le scritture restano a filo singolo e le azioni portano decisioni
   implicite che vanno rese esplicite, altrimenti "conflicting decisions carry
   bad results".

Confidence: 90% sui punti 1, 2, 4, 5, 6 (documentazione ufficiale letta e
verificata). 70% sul punto 3: due studi osservazionali con esiti opposti sul
beneficio.

## Cosa è cambiato nel file

| Sezione | Prima | Dopo | Perché |
|---|---|---|---|
| Segreti | 114 B | 362 B | failure log del 2026-11-26 (token in transcript) |
| Tool di casa | 786 B | 539 B | tolta porta sbagliata (`:9474`, reale `:9473`), comandi rimandati alle skill |
| Skill | 804 B | 804 B | invariate, aggiunta solo `handoff` |
| Ponytail | 1,1 kB | ~0,6 kB | le regole le inietta già il plugin, restano solo i casi di cambio livello |
| Quota GLM | 563 B | 396 B | compressa |
| Subagenti | assente | ~0,8 kB | nuova |
| Orchestrazione | assente | ~0,9 kB | nuova |

Lingua, Contesto, Anomalie, Comportamento: identiche all'originale.
Totale: 82 righe / 5,7 kB → 92 righe / 6,6 kB. Cresce di ~180 token a sessione
nonostante i tagli, perché le due sezioni nuove le hai chieste tu.

## Come è stata fatta

- Dati di prima parte: misura del file, elenco reale di skill e plugin, README
  e skill di inter-session e interserver.
- Due subagenti in parallelo (uno sulla documentazione ufficiale, uno su
  praticanti e paper), poi **verifica diretta di 32 citazioni** sulle pagine
  sorgente: tutte confermate.
- Le cifre sui token sono stime (byte / 3,7), non una tokenizzazione esatta.

## Revisione avversaria

- **"Il file cresce, e la ricerca dice di accorciare."** Vero. La crescita è
  dovuta solo alle sezioni che hai chiesto. Se vuoi scendere sotto l'originale,
  i candidati sono i 4 principi (sovrapposti al prompt di Ponytail, ~1,5 kB).
- **"I casi d'uso dei livelli Ponytail sono fonti?"** No. Vengono dal giudizio,
  non dal plugin: la sua documentazione definisce solo cosa fa ogni livello.
- **"L'allarme 4× / 15× si applica qui?"** È misurato da Anthropic sui suoi
  modelli, non su GLM. vale come ordine di grandezza.
- **"La sezione Orchestrazione è letteratura?"** La parte sul protocollo viene
   dai tuoi README (prima parte). La parte su assunzioni e filo singolo viene da
   Cognition (parere di un praticante, non uno studio).

<details>
<summary>Gap ledger</summary>

| Gap | Classe | Stato |
|---|---|---|
| Effetto misurato dei file a livello utente (non di repo) | open-in-world | aperto: nessuno studio trovato |
| Confronto `unslop` vs `human-writing` (due skill sovrapposte) | needs-user-input | aperto |
| Token esatti del file | closable-by-tool | chiuso come stima |

</details>

## Fonti

**Documentazione ufficiale**
- https://code.claude.com/docs/en/memory
- https://code.claude.com/docs/en/sub-agents
- https://www.anthropic.com/engineering/building-effective-agents
- https://www.anthropic.com/engineering/multi-agent-research-system
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- https://agents.md

**Paper**
- Liu et al., "Lost in the Middle: How Language Models Use Long Contexts", TACL 2024 (arXiv 2307.03172)
- Gloaguen et al., "Evaluating AGENTS.md: Are Repository-Level Context Files Helpful for Coding Agents?", 2026 (arXiv 2602.11988)
- Lulla et al., "On the Impact of AGENTS.md Files on the Efficiency of AI Coding Agents", 2026 (arXiv 2601.20404)
- Hong, Troynikov, Huber, "Context Rot", Chroma Research, 2025

**Praticanti**
- https://humanlayer.dev/blog/writing-a-good-claude-md
- https://humanlayer.dev/blog/stop-claude-from-ignoring-your-claude-md
- https://cognition.com/blog/dont-build-multi-agents
- https://cognition.com/blog/multi-agents-working

**Prima parte (locali)**
- `~/Desktop/Craftale/internal/interserver/README.md`
- skill `inter-session` e `interserver`
