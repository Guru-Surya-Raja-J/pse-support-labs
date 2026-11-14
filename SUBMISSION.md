# Submission

- **Name:** Guru Surya Raja J
- **Date submitted:** 14 November 2026
- **Repository link:** _<fill in: your own GitHub repo URL>_
- **Total time spent (real time):** about 3 h 15 min (13 Nov 21:00–23:00, 14 Nov 10:00–11:15 IST; see time log)

> Replies below are drafts written on the **exercise clock** (Monday 16 November 2026, Asia/Dubai). Keep your real time in the time log at the end. Put screenshots, log excerpts and query output in `evidence/` and link to them.

> **Note on timestamps in `evidence/`:** I ran the lab on my laptop on 14 Nov 2026 (real time). Log lines, Prometheus samples and database rows therefore carry real UTC timestamps (around 05:20–05:40Z). In the investigation logs below I map each step onto the exercise clock. The SQL behind every query output is next to it in `evidence/qNN-*.sql`, and the helper scripts I ran are in [`evidence/scripts/`](evidence/scripts/).

- **Items I fully investigated, and why I chose them:** All five have a root cause with evidence. In priority order:
  - **02 (API restarts)** is the P1, platform-wide.
  - **01 (Oasis)** and **04 (Sahara/Bluepeak)** both turned out to be caused by defects underneath item 02, so working them together was the efficient choice.
  - **03 (Al Noor, BR-CO-15)** is a separate product defect with an auditor waiting.
  - **05 (Ghaf)** is the product working as documented. It needed a clear, kind explanation rather than an escalation, so it took the least time.

### Summary of findings

| # | Item | Priority | Root cause (short) | Outcome |
|---|---|---|---|---|
| 02 | API restarted ×3 / 502s / "Validated" stuck | **P1** | The API is OOM-killed at its 128 MB limit. Every uploaded file and its parsed workbook is kept in memory forever (`SourceCache`, no eviction). Each kill drops the in-memory submission queue and leaves imports half-done. | Escalated to L3 (paged). Workaround: "Retry stuck invoices" recovers *Validated* invoices. |
| 01 | Oasis upload stuck, "already exists" | **P1** | A 600-line file takes ~122 s to validate (one ~200 ms Peppol lookup per row). The portal proxy gives up after 60 s, but the import keeps running server-side. Re-uploads then collide with the first import (AE-BR-09). The OOM in item 02 can also kill the import halfway, leaving orphan invoices. | Customer told exactly what was sent. Do not re-upload. Escalated for data repair plus timeout fix. |
| 04 | Sahara "Submitted", buyer missing invoices | **P1** | The ASP's fair-use limit (burst 8, then 2/s) returns **HTTP 429**. The API's submitter has no branch for 429, so the invoice stays "Submitted" forever with no ASP reference. Retry is blocked (409). 32 of 40 Sahara invoices never left Invoicely; 595 invoices are affected across 5 sellers. | Escalated to L3 for code fix and data repair. Told Bluepeak **not** to resend. |
| 03 | Al Noor BR-CO-15 | **P2** | The portal calculates "total with VAT" from **unrounded** qty × 3-decimal price × 1.05 instead of net + VAT (`pint.go:171`). It drifts 0.01–0.02 from net + VAT and the ASP rejects it. The customer's data is correct. | Escalated to L3. Written explanation for the auditor. Re-upload the 3 invoices after the fix. |
| 05 | Ghaf Café date error | **P3** | Dates typed as text `13/11/2026`. The template requires `YYYY-MM-DD` (AE-BR-04, documented). | Explained kindly with a 2-step fix. Verified: the corrected file gives 4/4 Accepted. Not escalated; raised a UX suggestion. |

---

## Incident 1 — `inbox/01-oasis-builders-upload-stuck.md`

### Acknowledgement

- **Sent at (exercise clock):** Mon 16 Nov 09:15 (received 09:05)
- **Reply:**

> Subject: RE: URGENT - monthly invoice upload stuck on "Processing"
>
> Dear Rashid,
>
> Thank you for the clear write-up, and I'm sorry this has landed on your month-end morning. My name is Guru and I'm looking after this for you personally.
>
> I understand that your November file sat on "Processing" twice, the third attempt showed an error page, and some invoices now say the document number "already exists". You need to know which November invoices have actually been sent, and how to send the rest without duplicates.
>
> Please don't upload the file again for now. You were right to stop. The portal blocks duplicate invoice numbers, so nothing can be issued twice. But further uploads make the picture harder to untangle.
>
> I'm checking each of your November invoices on our side right now, including what our Accredited Service Provider (the network partner that delivers e-invoices to your customers) has actually received. I'll email you that invoice-by-invoice list by 10:00. I'm also happy to call you on +971 6 555 0142 at that point if that's easier.
>
> Kind regards,
> Guru
> Product Support, Invoicely Lite

### Priority and justification

- **Priority:** **P1**. I started at P2 and raised it at 09:50 once item 02 showed it was part of a platform incident.
- **Why:** A whole month's invoices (8 invoices, about AED 3.8 M including VAT) for one customer are not reliably reaching the ASP. The SLA matrix puts "no invoices reaching the ASP for one or more customers" at P1. The business impact adds to that: month-end close is blocked and the customer's own customers are waiting. At 09:05 it looked like one customer with one large file (P2). At 09:50 the evidence from item 02 showed the same API crashes kill imports halfway, so I raised it to P1 and told Rashid why in the 10:00 update.
- **SLA deadlines I am working to:** First response by 09:35 (sent 09:15). Updates every 30–60 min (10:00, 11:00, 12:00 …). Resolution target 13:05.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 09:10 | Read the sample file description in `README.md` | Oasis: 8 invoices / **600 lines**. Desert Rose baseline (my clean upload): 5 invoices / 12 lines, completed in 2.5 s, all Accepted, each with an ASP reference. |
| 09:20 | DB: import durations per seller ([q01-overview.out.txt](evidence/q01-overview.out.txt)) | Every seller's imports average **2.6 s**. Oasis's November import took **121.9 s**. |
| 09:25 | Code: [`validate.go:166`](services/api/internal/validate/validate.go#L166) | Each row does a synchronous Peppol participant lookup. asp-mock sleeps 200 ms per lookup ([`asp-mock/main.go:40`](services/asp-mock/main.go#L40)). 600 rows × 0.2 s ≈ 120 s, which matches the 121.9 s exactly. |
| 09:30 | Code: [`web/app/api/[...path]/route.ts:6`](web/app/api/%5B...path%5D/route.ts#L6) | The portal proxy aborts after **60 s** and returns 504 "Gateway Timeout". The browser shows an error. |
| 09:32 | Code: [`importer.go:38`](services/api/internal/importer/importer.go#L38), [`:87`](services/api/internal/importer/importer.go#L87), [`:125`](services/api/internal/importer/importer.go#L125) | The import runs on `context.Background()` with a 10-minute budget, so it keeps going after the browser gives up. Invoices are written to the DB as Parsed (line 87) **before** validation. They are queued for the ASP only at the very end (line 125). |
| 09:35 | Code: [`store.go:301`](services/api/internal/store/store.go#L301) | The AE-BR-09 duplicate check matches any invoice with the same number in **another import** whose status is not Rejected. That includes Parsed or Validated invoices of an import that is still running or was killed. |
| 09:40 | **Reproduced** by uploading the real `samples/oasis-builders-nov-2026.xlsx` three times through the portal proxy ([01-repro-portal-upload.txt](evidence/01-repro-portal-upload.txt), [01-logs-repro.txt](evidence/01-logs-repro.txt)) | Attempt 1: **504 after 60.1 s**, but the import carried on server-side. Attempt 2: **502 after 0.2 s**, because the API was OOM-killed (third kernel OOM line in [02-oom-kills.txt](evidence/02-oom-kills.txt)) and attempt 1's import died halfway. Attempt 3: 504 after 60 s, then server-side all 8 invoices were **Rejected AE-BR-09 "already exists … with status 'Validated'/'Parsed'"**. This is exactly what Rashid saw. |
| 09:50 | Linked to item 02 and raised to P1 | The 502 and the half-finished import are the OOM restarts from item 02. |
| 09:55 | DB: per-invoice state of every Oasis November import ([q01-oasis.out.txt](evidence/q01-oasis.out.txt), [q01-oasis-replay.out.txt](evidence/q01-oasis-replay.out.txt)) | This morning's replay of Rashid's upload (`make load`, import `407a9872`) finished server-side after 121.9 s with **8/8 Accepted**, each with an ASP reference. My repro shows the bad branch: when the OOM hits during the first import, 4 invoices are left Validated and 4 Parsed, **none sent**, and they block the numbers. |
| 10:00 | Sent the update (below) | |
| _Dead end_ | Suspected the file itself (bad rows) or a real duplicate in the customer's data | Ruled out. The file parses cleanly (600 rows → 8 invoices, no portal rule failures other than AE-BR-09), and the "duplicates" all point to the same file's earlier import IDs. |
| _Dead end_ | Suspected the ASP was slow on submissions | Ruled out. ASP submit latency is 0–7 ms in the logs. The time is spent in **participant lookups during validation**, before anything is submitted. |

### Root cause

- **What happened:** The upload is synchronous. A 600-line file takes ~2 minutes to validate, but the portal gives up after 60 seconds and shows "Processing" followed by an error. The server keeps processing in the background. Each re-upload is a new import that collides with the first, giving AE-BR-09 "already exists". When the API is also OOM-killed during the import (item 02), the first import is left half-finished. Its invoices stay Parsed or Validated, are never sent, and still block the invoice numbers.
- **Where:**
  - `services/api/internal/validate/validate.go:166`: one ~200 ms participant lookup per row, sequential, not cached per buyer. All 600 rows have the same few buyers.
  - `web/app/api/[...path]/route.ts:6`: 60 s proxy timeout on a request that can take 2+ minutes.
  - `services/api/internal/importer/importer.go:38,87,125`: the import runs detached from the request. Invoices are persisted before validation and queued only at the end.
  - `services/api/internal/store/store.go:301`: the AE-BR-09 check counts Parsed or Validated invoices from other, unfinished imports.
- **Why it happens:** Processing time grows with the number of **rows** (lookup latency × rows), not with the number of invoices. Oasis's "bigger month" crossed the 60 s proxy limit. Nothing tells the user that the import is still running, so retrying is the natural reaction, and each retry makes it worse.
- **Evidence:** Screenshot: [01-portal-oasis-ae-br-09.png](evidence/01-portal-oasis-ae-br-09.png) (Oasis batch rejected with "already exists"). [q01-overview.out.txt](evidence/q01-overview.out.txt) (121.9 s vs 2.6 s), [01-repro-portal-upload.txt](evidence/01-repro-portal-upload.txt) (504 / 502 / 504), [01-logs-repro.txt](evidence/01-logs-repro.txt) (web proxy `TimeoutError` at 60106 ms; api `import completed … validated 0, rejected 8, duration_ms 121895`), [q01-oasis.out.txt](evidence/q01-oasis.out.txt) (AE-BR-09 against import `8f2e6b25`), [q01-oasis-replay.out.txt](evidence/q01-oasis-replay.out.txt).
- **Confidence and open questions:** **High** on the mechanism; I reproduced it end to end. Open question: production may have kept or lost the first import, depending on whether the API was killed during it. The per-invoice answer to Rashid must therefore come from the database and the ASP's `GET /v1/documents?sender=0235:1003182746`, not from assumptions. In the replay all 8 were Accepted. I would confirm against production before sending.

### Customer resolution reply OR escalation note

- **Which one and why:** Both. The customer gets a factual answer to both questions now. Engineering gets an escalation because (a) orphan invoices in Parsed or Validated can only be cleaned up with a data repair, and (b) the timeout and lookup design is a product defect. It is attached to the item 02 P1 incident.

**Update to customer (10:00):**

> Dear Rashid,
>
> As promised, here is where things stand.
>
> **1. Which November invoices have been sent?**
> I checked each invoice against what our delivery partner received. Your first upload this morning was processed in full, even though your screen never showed it: all 8 November invoices, OBS-2611-001 to OBS-2611-008, were accepted and each has a delivery reference. You can see them in the portal under Batches → the first `oasis-builders-nov-2026.xlsx` batch, with status "Accepted" and an "ASP reference" on each line. They are on their way to your customers. Nothing has been sent twice.
>
> **2. What about the "already exists" messages?**
> Those come from your second and third uploads. Because the first upload had already gone through, the portal correctly refused to issue the same invoice numbers again. That is the duplicate protection working. You don't need to do anything with those batches.
>
> **What went wrong:** your November file has 600 lines, many more than usual. The portal checks every line, and for a file this size that takes about two minutes. The upload screen stops waiting after one minute and shows "Processing" or an error, even though the work carries on in the background. That is a problem on our side, not with your file, and I'm sorry it cost you a stressful morning.
>
> **What happens next:**
> - Please don't re-upload the November file. Everything in it has been issued.
> - Until we've fixed this, for very large files, upload once and then check the Batches page after 3–4 minutes rather than waiting on the upload screen. Or split the file into two or three smaller files of a few invoices each, which are processed in under a minute.
> - I've passed this to our engineering team so that large files are handled properly. We're also dealing with a wider stability issue this morning that I'm watching closely.
>
> I'll update you again by 11:00. If your controller needs a list of the 8 invoices with their delivery references for the close, reply and I'll send it straight away.
>
> Kind regards,
> Guru

> _Note for the case file:_ if the production data shows the **bad branch** (first import killed halfway, as in my repro: 4 Validated + 4 Parsed, none sent), the reply changes to: "None of the 8 invoices has reached your customers yet. Please do not upload again. I have asked engineering to release the invoice numbers that are stuck, and I will send them once, myself, and confirm each delivery reference to you by <time>." The data repair below covers this.

**Escalation note (attached to the item 02 incident):**

```markdown
### Escalation: Large uploads time out at 60 s in the portal; re-uploads hit AE-BR-09; orphan invoices block numbers

**Priority:** P1 (part of the API-restart incident, item 02). Oasis Builders' month-end close is blocked.
**Customer / seller:** Oasis Builders Supply LLC, seller_id 2 (Peppol 0235:1003182746)
**Reported by / at:** Rashid Al Mansoori, email, Mon 16 Nov 09:05
**Affected:** File oasis-builders-nov-2026.xlsx (600 rows, 8 invoices OBS-2611-001..008). Imports 407a9872 (completed, 8 Accepted), 8f2e6b25 (stuck Processing: 4 Validated, 4 Parsed), c5cee28e (stuck Processing, 0 rows), 54b88000 (8 Rejected AE-BR-09). The same risk applies to any file with more than ~250 rows.

**Symptoms (customer view):** Upload sits on "Processing", then an error page. Re-uploads show "Document number already exists".

**Evidence:**
- Web proxy log: `{"msg":"proxy","level":"error","method":"POST","path":"/imports","status":504,"durationMs":60106,"error":"TimeoutError..."}` (evidence/01-logs-repro.txt)
- API log: `"import completed" ... "rows":600,"invoices":8,"validated":0,"rejected":8,"duration_ms":121895`
- DB: Oasis imports take 121.9 s vs 2.6 s for every other seller (evidence/q01-overview.out.txt). AE-BR-09 rows point at import 8f2e6b25 (evidence/q01-oasis.out.txt).
- Metrics: invoicely_import_duration_seconds; participant lookup at ~200 ms each, 1 per row.

**Steps to reproduce:**
1. `curl -F file=@samples/oasis-builders-nov-2026.xlsx -F seller_id=2 http://localhost:3000/api/imports` → 504 after 60 s.
2. Repeat → 502 if the API is OOM-killed (item 02); otherwise a new import.
3. Check the batch: invoices Rejected AE-BR-09 against the first import.

**What I have already tried / ruled out:** The file is valid (no rule failures apart from AE-BR-09). ASP submit latency is ms-level, not the cause. The time is in validate.go participant lookups.

**Suspected cause (with confidence, high):**
- validate.go:166: sequential per-row participant lookup (600 × 200 ms). Cache it per buyer ID within an import.
- route.ts:6: 60 s proxy timeout on a synchronous upload. Make upload asynchronous (return 202 + import id, UI polls), or at least raise the timeout above the processing budget.
- importer.go:87/125 + store.go:301: invoices persisted before validation and queued only at the end. An import killed halfway leaves Parsed/Validated orphans that block numbers via AE-BR-09 and can never be retried.

**Workaround in place:** Partial. Customer told not to re-upload. For future large files: split, or upload once and check Batches after 3–4 min. "Retry stuck invoices" on 8f2e6b25 would send its 4 Validated invoices, but the 4 Parsed ones need a data fix.

**Timeline:**
- 09:05 email received · 09:15 ack · 09:40 reproduced · 09:50 linked to item 02, raised to P1 · 10:00 customer update

**Ask:**
1. By 12:00: confirm in production which OBS-2611 invoices have an asp_message_id. If any import was left with Parsed/Validated orphans, mark them Rejected with detail "Superseded – import interrupted" (frees the numbers), so I can resend once and confirm to the customer.
2. Code fix (cache lookups; async upload or timeout ≥ processing budget) scheduled before the next month-end.
**Next customer update due:** 11:00
```

### Workaround offered

- **Now:** don't re-upload. The customer gets the list of invoices that have been issued. If any invoices were orphaned, engineering releases the numbers and I resend once.
- **Until fixed:** split very large files into smaller files (a few invoices each, under ~250 rows, so under 60 s), or upload once and check the Batches page after 3–4 minutes instead of waiting on the upload screen.

### Prevention ideas

- Cache participant lookups per buyer within an import (600 lookups become ~4), or validate rows concurrently.
- Make the upload asynchronous: return `202` with the import id straight away, and have the upload page poll the batch status, so the browser timeout no longer matters.
- Insert invoices and queue them in a single transaction at the end of an import, or sweep imports stuck in "Processing" and roll back their invoices so they don't block numbers.
- Product: show a clear "Your file is still being processed, don't upload again" state, and when AE-BR-09 points at an earlier batch, say which one.
- Monitoring: an alert when `import duration p95 > 45 s` (close to the proxy limit) and when any import has been "Processing" for more than 10 minutes.

---

## Incident 2 — `inbox/02-alert-api-restarted-marina-bay.md`

### Acknowledgement

- **Sent at (exercise clock):** 09:52 to Priya (received 09:50; Grafana alert at 09:42). Engineering on-call paged at 09:50.
- **Sent to:** Priya Nair (CSM) in #cs-escalations / email, cc support-oncall. Page to L3 on-call.
- **Reply:**

> Hi Priya, thanks for forwarding. I'm owning this as a **P1**. Yes, it's the same thing: the API has restarted 3 times since about 09:30. Each restart briefly drops in-flight requests (that's the 502s on upload), and invoices that were waiting to be sent at that moment are left in "Validated". I've paged engineering on-call and I'm investigating now.
>
> For your customers right now: if an invoice has been in "Validated" for more than 15 minutes, **"Retry stuck invoices"** on the batch page sends it again safely. Please ask them **not** to re-upload whole files, because that creates "already exists" errors.
>
> On Marina Bay for Wednesday: I'll give you a clear yes/no with reasons by **12:30**, ahead of your afternoon call, plus a short note you can use with their GM. Next update to you by 10:30.
> — Guru

### Priority and justification

- **Priority:** **P1**
- **Why:** A production API crash loop. The alert is `severity=critical`, several customers are getting 502s on upload, and invoices are not reaching the ASP (stuck in Validated). By the SLA definition (production down or invoices not reaching the ASP for one or more customers) this is P1, and the policy says page engineering as soon as impact is confirmed, without waiting for a full root cause. Business impact: Marina Bay goes live on Wednesday 18 Nov and the CSM needs an answer before this afternoon's call. It was also likely to be the root of other tickets (it turned out to be behind 01 and part of 04). **I worked this one first** from 09:50.
- **SLA deadlines I am working to:** First response by 10:12, 15–30 min after 09:42 (sent 09:52). Updates every 30 min while the incident is active (10:30, 11:00 …). Resolution target 13:42. Marina Bay go/no-go answer to Priya by 12:30.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 09:50 | Grafana "Invoicely Lite – Overview" ([P1_Evidence.png](evidence/P1_Evidence.png)) | **API process restarts = 3**. Request latency p95 spikes into minutes. "Submission queue" = 0 (misleading, see 10:40). |
| 09:52 | Paged L3 on-call. Acked Priya. | |
| 09:55 | `docker inspect invoicely-lite-api-1` | `RestartCount` climbing. Limit `Memory=134217728` (128 MB) with `MemorySwap` also 128 MB, so no swap headroom ([02-oom-kills.txt](evidence/02-oom-kills.txt)). `State.OOMKilled` showed false, but that flag is reset on restart, so I didn't trust it. |
| 10:00 | API logs immediately before each restart ([02-api-log-before-restarts.txt](evidence/02-api-log-before-restarts.txt)) | **No error, no panic.** Normal `asp response` and `import received` lines, then `api starting`. The process was killed from outside, not crashing in Go. |
| 10:05 | Kernel log (`dmesg` in the Docker VM) ([02-oom-kills.txt](evidence/02-oom-kills.txt)) | `Memory cgroup out of memory: Killed process (api) anon-rss:129272kB`, repeated for each restart, at the 128 MB cgroup limit. **Confirmed OOM kill.** |
| 10:10 | Prometheus `go_memstats_heap_inuse_bytes{job="api"}` ([02-prometheus.txt](evidence/02-prometheus.txt)) | The heap sits at ~10–17 MB all morning, then climbs during the upload peak to **119.5 MB max**. After the peak it **stays at ~87 MB** with no traffic, so memory is not released. |
| 10:15 | Code: what is held per upload? [`importer.go:95`](services/api/internal/importer/importer.go#L95), [`sources.go:24-31`](services/api/internal/importer/sources.go#L24-L31) | Every upload stores `Raw` (file bytes), the full parsed **excelize workbook** and the mapped invoices in `SourceCache`, a plain map **with no eviction or TTL**. Memory grows with every upload until the 128 MB limit, and then the kernel kills the process. |
| 10:20 | Code: what is lost on restart? [`submit.go:65,72`](services/api/internal/submit/submit.go#L65), [`importer.go:125`](services/api/internal/importer/importer.go#L125) | The submission queue is an **in-memory Go channel**. Invoices queued but not yet sent are lost when the process dies, and nothing re-queues them on start-up. That's why invoices "sit in Validated". Imports being processed at the moment of the kill stay in "Processing" with Parsed invoices forever. |
| 10:25 | DB: impact ([q01-overview.out.txt](evidence/q01-overview.out.txt), [q02-marina.out.txt](evidence/q02-marina.out.txt)) | Platform-wide: **28 invoices stuck in Validated, 38 Parsed, 14 imports stuck in "Processing"** (4 sellers plus Oasis). **Marina Bay:** 7 Validated, 11 Parsed, 3 imports Processing, **plus 143 stuck in "Submitted"** (the separate defect, see item 04). |
| 10:30 | Update to Priya | |
| 10:35 | **Tested the workaround** on Marina Bay batch `742e5f7d` ([02-retry-workaround.txt](evidence/02-retry-workaround.txt)) | `POST /v1/imports/{id}/retry` → `requeued 5` → **5/5 Accepted** within seconds. The 1 Parsed invoice cannot be retried, and the batch stays "Processing". |
| 10:40 | Why does the dashboard show "Submission queue = 0" when hundreds of invoices are stuck? | The gauge counts only the in-memory channel ([`submit.go:71`](services/api/internal/submit/submit.go#L71)). It resets on restart and never counts invoices stuck in Submitted. **The monitoring hides the backlog.** |
| 10:45 | Prometheus ASP-side counters ([02-prometheus.txt](evidence/02-prometheus.txt)) | `asp_documents_total{outcome="throttled"}` = **595**. Exactly the number of invoices stuck in Submitted. That led to item 04's root cause (the second defect behind the Marina Bay risk). |
| 12:30 | Marina Bay go/no-go to Priya (below) | |
| _Dead end_ | Database or ASP outage? | Ruled out. Postgres and asp-mock stayed healthy, `RestartCount=0` for asp-mock, and the healthchecks were green. |
| _Dead end_ | Go panic or bug in a handler? | Ruled out. No panic or stack trace in the logs, the exit is a SIGKILL, and the kernel OOM lines match each restart. |
| _Dead end_ | cAdvisor "Container memory" panel to show the memory climb | In my WSL2 set-up cAdvisor didn't export the compose labels, so the panel was empty. I used the Go heap metric plus the kernel OOM log instead (a stronger signal anyway). |

### Root cause

- **What happened:** The API process was OOM-killed by the kernel 3 times during the morning upload peak. Each kill caused 502s for in-flight requests (uploads especially), dropped every invoice waiting in the in-memory submission queue (left in "Validated"), and froze any import being processed at that moment ("Processing", invoices "Parsed").
- **Where (component, `file:line`):**
  - `services/api/internal/importer/sources.go:24,31` and `importer.go:95`: `SourceCache` keeps every uploaded file **and** its parsed workbook in memory forever (no eviction). This is the leak.
  - `docker-compose.yml:60-61`: `mem_limit: 128m`, `memswap_limit: 128m` on the api, so there is very little headroom.
  - `services/api/internal/submit/submit.go:65,72`: queue is an in-memory channel. `importer.go:125`: invoices are enqueued only at the end of an import. Nothing re-queues Validated invoices at start-up (`main.go:56-57`). This is why the impact outlasts the crash.
- **Why it happens:** Memory scales with the number and size of uploads since the last restart, not with current load. At peak (~150 uploads in a few minutes) it crosses 128 MB. A restart frees the memory, so the cycle repeats at the next busy period.
- **Evidence:** Screenshots: [02-grafana-heap.png](evidence/02-grafana-heap.png) (Go heap climbs to ~120 MB and drops to zero at each OOM kill, around 10:56, 10:57 and 11:07 IST), [P1_Evidence.png](evidence/P1_Evidence.png) (overview: 3 restarts). [02-oom-kills.txt](evidence/02-oom-kills.txt) (kernel OOM kills, anon-rss ≈ 129 MB), [02-api-log-before-restarts.txt](evidence/02-api-log-before-restarts.txt), [02-prometheus.txt](evidence/02-prometheus.txt) (heap max 119.5 MB, ~87 MB retained, throttled = 595), [P1_Evidence.png](evidence/P1_Evidence.png) (dashboard: 3 restarts), [q02-marina.out.txt](evidence/q02-marina.out.txt), [02-retry-workaround.txt](evidence/02-retry-workaround.txt).
- **Confidence and open questions:** **High** that the restarts are OOM kills caused by the unbounded `SourceCache`. Open question: whether the excelize `File` object (with its XML trees) is the biggest item per entry. A heap profile (`pprof`) would confirm, and I listed it in the ask.

### Customer resolution reply OR escalation note

- **Which one and why:** **Escalation to L3** (paged at 09:50, full note below). It's a P1 product defect in code and configuration that support can't fix, and the stuck Parsed invoices need a data repair. I keep ownership of the internal customer (Priya) and the affected sellers.

```markdown
### Escalation: API OOM-killed at 128 MB during upload peak → 502s, invoices stuck in Validated/Parsed, imports stuck in Processing

**Priority:** P1. Production API crash-looping (3 restarts in 15 min, alert InvoicelyApiRestarted). Multiple customers affected. Marina Bay Hospitality go-live Wed 18 Nov.
**Customer / seller:** Platform-wide. Confirmed: Marina Bay (3), Desert Rose (1), Palm Coast (7), Zayed Port (8), Oasis (2).
**Reported by / at:** Grafana alert 09:42; Priya Nair (CSM) 09:50
**Affected:** 3 OOM kills since ~09:30. 28 invoices stuck Validated, 38 Parsed, 14 imports stuck Processing (evidence/q02-marina.out.txt, q01-overview.out.txt).

**Symptoms (customer view):** "502 Bad Gateway" on and off, mostly on upload. Invoices sitting in "Validated". Some batches stay "Processing" forever.

**Evidence:**
- Kernel: `Memory cgroup out of memory: Killed process 13620 (api) total-vm:1409596kB, anon-rss:129272kB` (one line per restart, evidence/02-oom-kills.txt)
- docker inspect: Memory=134217728, MemorySwap=134217728 (docker-compose.yml:60-61)
- Logs: no panic/error before each `"msg":"api starting"` (evidence/02-api-log-before-restarts.txt). Query: `{service="api"} | json | msg="api starting"`
- Metrics: `go_memstats_heap_inuse_bytes{job="api"}`: ~15 MB baseline → 119.5 MB peak, ~87 MB retained after the peak with no traffic. `changes(process_start_time_seconds{job="api"}[15m])` = 3.
- DB: `SELECT status,count(*) FROM invoices WHERE status IN ('Parsed','Validated') AND updated_at < now()-interval '15 min' GROUP BY 1;`

**Steps to reproduce:** `make reset && make load` → watch "API process restarts" and the Go heap panel during the peak phase. Or upload samples/oasis-builders-nov-2026.xlsx twice in a row after a peak.

**What I have already tried / ruled out:** Not DB/ASP (both healthy, asp-mock RestartCount=0). Not a Go panic (no stack traces). "Retry stuck invoices" recovers Validated invoices (tested: 5/5 Accepted on batch 742e5f7d) but not Parsed ones.

**Suspected cause (high confidence):** importer/sources.go:24-31 + importer.go:95: SourceCache stores raw file + parsed excelize workbook per upload with no eviction → unbounded heap → OOM at 128 MB. Made worse by submit.go:65 (in-memory queue lost on restart, nothing re-queues Validated at start-up).

**Workaround in place:** Yes, partial. CSMs/customers use "Retry stuck invoices" for anything Validated > 15 min. Asked customers not to re-upload whole files.

**Timeline:**
- ~09:30 first restart · 09:42 alert · 09:50 CSM report, paged on-call · 10:05 OOM confirmed · 10:15 SourceCache identified · 10:35 workaround verified

**Ask:**
1. **Now (mitigation):** raise api mem_limit (e.g. 512 MB) and restart, so customers stop getting 502s today.
2. **Today:** bound SourceCache (LRU/TTL, or store only the raw bytes on disk/S3 and re-parse on demand; drop the excelize File after parsing). Confirm with a heap profile.
3. **Today (data repair):** re-queue all Validated invoices; for the 14 imports stuck in Processing, finish validation or mark the Parsed invoices Rejected ("import interrupted") so customers can re-upload.
4. **This week:** on start-up, re-enqueue Validated/Failed invoices (durable queue or DB-driven poller).
**Next customer update due:** 10:30 (Priya), then every 30 min
```

**Marina Bay go/no-go update to Priya (12:30), the internal customer for this item:**

> Hi Priya, here's where we are before your call.
>
> **What happened this morning:** two separate product problems, both understood and with engineering.
> 1. The API ran out of memory during the busy upload period and restarted 3 times. That caused the 502s and the invoices stuck in "Validated". Engineering is raising the memory limit as an immediate fix and correcting the underlying memory leak.
> 2. More important for Marina Bay: when a customer sends more than 8 invoices in a short burst, our delivery partner (the ASP) asks us to slow down, and our system doesn't send those invoices again. They show "Submitted" but never arrive. Marina Bay currently has **143 invoices in this state from this morning's peak** (they haven't reached their buyers). Engineering will re-send them safely once the fix is in.
>
> **Are we OK for Wednesday?** **Not yet, and I'd rather say so now.** With the code as it is today, Marina Bay's normal daily volume would hit problem 2. My recommendation for your call: keep Wednesday provisionally, conditional on (a) the retry fix for problem 2 being deployed and (b) a test upload at their real volume passing end-to-end on Tuesday. I'll confirm (a) with engineering by 16:00 today and will run (b) with you on Tuesday. If either isn't green by Tuesday 15:00, we move go-live by a few days rather than risk invoices going missing.
>
> **What you can tell their GM:** "We found and are fixing an issue that affects high-volume sending. Nothing has been lost: every affected invoice is tracked and will be delivered. We'll confirm on Tuesday after a full-volume test."
>
> Next update from me: 16:00 today.
> — Guru

### Workaround offered

- For invoices **Validated > 15 min**: "Retry stuck invoices" on the batch page. Verified: 5/5 Accepted.
- Ask customers **not** to re-upload whole files, which causes AE-BR-09 duplicate errors (item 01).
- Batches stuck in **Processing** with Parsed invoices: no customer-side workaround. Covered by the data repair in the escalation.
- Mitigation requested from L3: raise the api memory limit now.

### Prevention ideas

- Bound the `SourceCache` (LRU + TTL); keep only the raw bytes, ideally in object storage, and re-parse on demand for the "Source rows" view.
- A durable submission queue, or a poller that picks up `Validated`/`Failed` invoices from the DB, so a restart never loses work.
- Reconcile imports stuck in `Processing` at start-up.
- Monitoring: alert on container memory > 80% of the limit (before the OOM), not only after restarts. Alert on "invoices in Validated > 15 min" and "imports Processing > 10 min" using DB-based metrics. Fix the "Submission queue" panel, which shows 0 while hundreds are stuck.
- Load-test at peak volume (the `make load` profile) before each release and before a big customer goes live.

---

## Incident 3 — `inbox/03-al-noor-fuel-br-co-15.md`

### Acknowledgement

- **Sent at (exercise clock):** 10:40 (received 10:15)
- **Reply:**

> Subject: RE: Invoices rejected with BR-CO-15 – November fuel invoices
>
> Dear Ms Khoury,
>
> Thank you for your email and for attaching the file. My name is Guru and I'm handling this for you.
>
> I understand that several of your November fuel invoices were rejected with BR-CO-15, a check that the invoice total including VAT equals the total excluding VAT plus the VAT, even though your figures come straight from your dispatch records and other invoices prepared the same way were accepted.
>
> I'm looking at the rejected invoices and how their totals were calculated now. The rejected invoices were not delivered to your customers, and they don't "use up" their invoice numbers, so they can be issued again with the same numbers once we know the cause. Please don't change your figures in the meantime.
>
> I'll come back to you by 13:00 today with an explanation in writing that you can share with your auditor.
>
> Kind regards,
> Guru
> Product Support, Invoicely Lite

### Priority and justification

- **Priority:** **P2**
- **Why:** A subset of invoices is rejected (3 of 6 in this file) for one customer, and the rest go through. That is the SLA definition of P2. It isn't P1, because the customer can still issue other invoices. It is more than P3, because there is compliance exposure (an external auditor is reviewing the November VAT position) and the cause turned out to be a product defect likely to affect every customer with 3-decimal unit prices.
- **SLA deadlines I am working to:** First response by 11:15 (sent 10:40). Updates every 2–4 h (13:00, then 16:00). Resolution target 18:15 today, in business hours.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 10:45 | DB: Al Noor invoices with totals ([q03-al-noor.out.txt](evidence/q03-al-noor.out.txt)) | 3 of 6 November invoices Rejected **by ASP**, BR-CO-15: ANF-2611-0042 (−0.01), -0044 (−0.02), -0046 (−0.01). On each, `total_incl_vat` ≠ `total_excl_vat + total_vat`. The accepted ones match exactly. |
| 10:50 | ASP error detail | e.g. `Got 5610.99, expected 5611.00`. The ASP adds IBT-109 + IBT-110 and compares with IBT-112. |
| 10:55 | Checked the customer's data against the template rules (`docs/template-field-guide.md`) | Every line net = qty × 3-decimal price **rounded to 2 decimals**, which is exactly what the template requires (AE-BR-08 passed). **The customer's data is correct.** |
| 11:00 | Code: [`pint.go:165-185`](services/api/internal/pint/pint.go#L165-L185) | `net` and `vat` are summed from the **rounded** line amounts, but `gross += l.Quantity * l.UnitPrice * (1 + l.VATRate/100)` (**line 171**) uses the **unrounded** qty × price. `TaxInclusiveAmount = round2(gross)` (line 184). |
| 11:10 | Recalculated independently in Python with exact decimals ([03-br-co-15-worked-example.txt](evidence/03-br-co-15-worked-example.txt)) | The difference reproduces the ASP's "Got/expected" **to the cent** for all 3 invoices. Example: ANF-2611-0046, line 1: 1512 × 2.917 = 4410.504 → net 4410.50. Portal gross = (4410.504 + 933.30) × 1.05 = 5610.9942 → **5610.99**, but net 5343.80 + VAT 267.20 = **5611.00**. |
| 11:15 | Why do some pass? | Invoices whose qty × price is already a whole number of fils (e.g. 18.45 × 24 = 442.80), or where the rounding happens to cancel out, give no drift. It looks random to the customer, which explains "prepared the same way". |
| _Dead end_ | Thought it might be VAT rounding per line vs per category (BR-CO-14) | Ruled out. BR-CO-14 passes; the VAT breakdown matches the total VAT. Only IBT-112 is computed from a different basis. |

### Root cause

- **What happened:** For invoices with 3-decimal unit prices (litre-priced fuel), the portal calculates "Invoice total with VAT" (IBT-112) from the unrounded quantity × price. It calculates "total without VAT" (IBT-109) and "total VAT" (IBT-110) from the rounded line amounts. The two can differ by 0.01–0.02 AED, and the ASP's BR-CO-15 rule rejects the invoice.
- **Where:** `services/api/internal/pint/pint.go:171` (gross accumulation) and `:184-185` (`TaxInclusiveAmount`/`PayableAmount = round2(gross)`).
- **Why it happens:** IBT-112 should be IBT-109 + IBT-110 by definition. Calculating it independently from unrounded inputs breaks that identity whenever line rounding is involved.
- **Evidence:** [q03-al-noor.out.txt](evidence/q03-al-noor.out.txt) (totals, lines, ASP errors), [03-br-co-15-worked-example.txt](evidence/03-br-co-15-worked-example.txt) (independent recomputation matching the ASP to the cent), code reference above.
- **Confidence and open questions:** **High.** Open questions: (1) other sellers with 3-decimal prices are probably affected; engineering should query `invoices WHERE errors->0->>'rule'='BR-CO-15'` platform-wide. (2) The fix changes no amounts the customer typed, only how the portal derives IBT-112, so no customer data has to change.

### Customer resolution reply OR escalation note

- **Which one and why:** **Escalation to L3** (product defect in the PINT mapping; support can't work around it without the customer altering correct tax figures, which we must not ask for). Plus a written explanation to the customer and auditor.

**Customer update (13:00), written so it can go to the auditor:**

> Dear Ms Khoury,
>
> Thank you for your patience. Here is the explanation I promised. It's written so that you can forward it to your auditor.
>
> **1. Why were these specific invoices rejected?**
> Three invoices were rejected: ANF-2611-0042, ANF-2611-0044 and ANF-2611-0046. The cause is a calculation error in our portal, **not in your data**.
>
> Your file gives each line's net amount rounded to 2 decimals (for example 1,512 litres × AED 2.917 = 4,410.504, shown as 4,410.50), which is correct and what our template asks for. The portal correctly adds up those rounded line amounts for the total without VAT and the total VAT. But it calculated the total *including* VAT a different way, from the unrounded figures. On these three invoices that produced a total 1–2 fils lower than "total without VAT + VAT":
>
> | Invoice | Total without VAT | VAT | Should be | Portal sent | Difference |
> |---|---|---|---|---|---|
> | ANF-2611-0042 | 14,307.08 | 715.35 | 15,022.43 | 15,022.42 | 0.01 |
> | ANF-2611-0044 | 11,254.84 | 562.75 | 11,817.59 | 11,817.57 | 0.02 |
> | ANF-2611-0046 | 5,343.80 | 267.20 | 5,611.00 | 5,610.99 | 0.01 |
>
> The e-invoicing network checks that these three totals agree (rule BR-CO-15) and rejected the invoices. The other invoices in your file were accepted because their line amounts happened to have no rounding difference.
>
> **2. Do you need to correct anything?**
> No. Your quantities, prices and line amounts are correct. Please don't adjust them.
>
> **3. How and when can they be issued?**
> I've reported this to our engineering team with the full details, and they're correcting the calculation. Rejected invoices were not delivered to your customers and don't use up their numbers. Once the fix is live, you can upload **just these three invoices** again, unchanged, with the same invoice numbers. Please don't re-upload the accepted ones; the portal would block them as duplicates. I'll confirm the fix date as soon as engineering commits to it, and I'll check the three invoices are accepted with you.
>
> **For your auditor:** the three invoices were never issued on the network. The accepted invoices in the same file are correct as issued, and their totals agree exactly. Your VAT amounts are unaffected; the difference was only in the portal's calculation of the gross total.
>
> I'll update you by 16:00 today with the fix date.
>
> Kind regards,
> Guru

**Escalation note:**

```markdown
### Escalation: IBT-112 (total incl. VAT) computed from unrounded qty×price → BR-CO-15 rejections for 3-decimal prices

**Priority:** P2. Subset of invoices rejected; customer's auditor reviewing November VAT; likely affects all sellers using 3-decimal unit prices.
**Customer / seller:** Al Noor Fuel & Lubricants LLC, seller_id 4
**Reported by / at:** Fatima Khoury, email, Mon 16 Nov 10:15
**Affected:** ANF-2611-0042, -0044, -0046 (Rejected by ASP, BR-CO-15). Same file's -0041, -0043, -0045 accepted.

**Symptoms (customer view):** "BR-CO-15: Invoice total amount with VAT (IBT-112) must equal ... IBT-109 + IBT-110" on some invoices from a correct file.

**Evidence:**
- ASP response: 422, `BR-CO-15 ... Got 5610.99, expected 5611.00` (ANF-2611-0046)
- Payload: lines netAmount 4410.5 (1512 × 2.917 = 4410.504) + 933.3; totals taxExclusive 5343.80, tax 267.20, taxInclusive 5610.99
- DB: evidence/q03-al-noor.out.txt; independent recomputation: evidence/03-br-co-15-worked-example.txt (matches ASP to the cent for all 3)

**Steps to reproduce:** `make replay CUSTOMER=al-noor` → 3 of 6 Rejected by ASP, BR-CO-15.

**What I have already tried / ruled out:** Customer data is template-compliant (AE-BR-08 passes). BR-CO-10/BR-CO-14 pass. No workaround that doesn't involve altering correct figures.

**Suspected cause (high confidence):** services/api/internal/pint/pint.go:171 `gross += l.Quantity * l.UnitPrice * (1 + l.VATRate/100)` and :184-185 `round2(gross)`. Fix: `TaxInclusiveAmount = round2(net) + round2(vat)` (and PayableAmount likewise).

**Workaround in place:** No. Customer asked to wait and not alter figures. Rejected invoices don't consume numbers, so re-upload after the fix is safe.

**Timeline:** 10:15 received · 10:40 ack · 11:10 root cause confirmed · 13:00 customer/auditor explanation

**Ask:**
1. Fix pint.go totals (+ unit test with 3-decimal prices) and give me a deploy date by 16:00 today.
2. Run a platform-wide query for BR-CO-15 rejections so I can proactively contact other affected sellers.
**Next customer update due:** 16:00
```

### Workaround offered

None that is safe. Asking the customer to round their unit prices to 2 decimals would change correct tax-invoice figures. Instead: wait for the fix, then re-upload **only** the 3 rejected invoices unchanged (rejected invoices don't use up numbers; re-uploading accepted ones would hit AE-BR-09).

### Prevention ideas

- Derive IBT-112 = IBT-109 + IBT-110 by construction. Add a unit test with 3-decimal quantity-priced lines.
- Pre-flight in the portal: run the same BR-CO-10/14/15 checks before submission, so this shows as a portal error with the row, not an ASP rejection.
- Add a regression sample (like `al-noor-fuel`) to the release test suite.
- Proactively notify other customers that have BR-CO-15 rejections.

---

## Incident 4 — `inbox/04-bluepeak-sahara-not-received.md`

### Acknowledgement

- **Sent at (exercise clock):** 11:40 (received 11:30)
- **Reply:**

> Subject: RE: Sahara Medical - invoices "Submitted" but buyer not receiving them
>
> Hi Daniel,
>
> Thanks for the detailed report, and for holding off on resending. That's the right call. I'm Guru from Invoicely support and I'm owning this.
>
> To confirm I've understood: your connector pushed Sahara Medical's 40-invoice batch this morning and got HTTP 201. The invoices show "Submitted" in the portal, many have no ASP reference, and Emirates Palm Hospital has received only a few.
>
> An empty ASP reference means our delivery partner hasn't confirmed receipt of that invoice, so I'm treating this as invoices not reaching the network, and as a top priority. I'm checking each of the 40 invoices against what the delivery partner actually received now.
>
> Please keep holding off on resending from the connector until I confirm. I'll update you and Sahara's IT team by 12:15 with what has and hasn't arrived and what happens next.
>
> Best regards,
> Guru
> Product Support, Invoicely Lite

### Priority and justification

- **Priority:** **P1**
- **Why:** Invoices are not reaching the ASP (32 of 40) for this customer, which is the SLA's P1 definition. It is also **silent**: the portal shows "Submitted", the connector got 201, and nothing alerts. Business impact: the hospital's payment run is this week. By 11:30 I already knew from item 02 that 595 invoices across 5 sellers were in this state, so this is part of the platform P1, not an isolated integration question. (Considered P2, "subset of invoices", but rejected that because the invoices are effectively lost without anyone being told.)
- **SLA deadlines I am working to:** First response by 12:00 (sent 11:40). Updates every 30–60 min (12:15, 13:00, 14:00 …). Resolution target 15:30.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 11:45 | DB: Sahara invoices ([q04-sahara.out.txt](evidence/q04-sahara.out.txt)) | Today's batch `d176ba80` (60 rows, 40 invoices): **8 Accepted with ASP ref, 32 "Submitted" with no ASP reference**. All 32 have the event history Parsed → Validated → Submitted ("Sent to ASP") at 05:24:01Z and **nothing after**. |
| 11:50 | Asked the ASP what it received: `curl "http://localhost:8090/v1/documents?sender=0235:1006453719"` ([04-asp-received-sahara.txt](evidence/04-asp-received-sahara.txt)) | The ASP has **only 8 documents** from Sahara today (SMS-1116-001…008), all accepted. **The other 32 never reached the ASP.** Invoicely is not losing them "on the network". They never left. |
| 11:55 | Why exactly 8? asp-mock code [`main.go:36-37`](services/asp-mock/main.go#L36-L37), [`:274-283`](services/asp-mock/main.go#L274-L283) | ASP fair-use limit: burst of **8**, then 2 per second per sender. Above that it returns **HTTP 429** + `Retry-After` ("the document has not been received and should be sent again later", `docs/architecture.md`). The submitter's 4 workers fired all 40 within ~0.1 s. |
| 12:00 | Logs ([04-asp-429-logs.txt](evidence/04-asp-429-logs.txt)) | asp-mock: `"rate limit exceeded" ... "retry_after_s":1`. api: `"asp response" ... "status_code":429`, and then nothing for that invoice. |
| 12:05 | Code: [`submit.go:114`](services/api/internal/submit/submit.go#L114), [`:133-155`](services/api/internal/submit/submit.go#L133-L155) | Status is set to **Submitted before** sending. The `switch resp.StatusCode` handles 200, 422 and 500/502/503/504 **only**. **429 falls through with no branch**, so the invoice stays "Submitted" with no ASP reference, no error and no retry. Forever. |
| 12:08 | Can the customer retry? ([04-retry-blocked.txt](evidence/04-retry-blocked.txt)) | `POST /v1/invoices/{id}/retry` → **409** "only invoices in status Validated or Failed can be retried (current status: Submitted)". Batch retry → `requeued 0`. **No self-service recovery.** |
| 12:10 | Scope ([q04-sahara.out.txt](evidence/q04-sahara.out.txt), [02-prometheus.txt](evidence/02-prometheus.txt)) | Invoices stuck Submitted with no ASP ref: Palm Coast 143, **Marina Bay 143**, Zayed Port 140, Desert Rose 137, Sahara 32 = **595**. `asp_documents_total{outcome="throttled"}` = **595**, an exact match. |
| 12:12 | Would resending from the connector create duplicates? Code [`store.go:301`](services/api/internal/store/store.go#L301) | No duplicates at the hospital, but it **wouldn't help either**. A "Submitted" invoice blocks its number, so a resend is rejected with AE-BR-09. Correct advice: don't resend. |
| _Dead end_ | Considered buyer-side issues (hospital's Peppol ID not registered, or their ASP) | Ruled out. The 8 that went through reached the same buyer, the participant lookup passes (AE-BR-11 not raised), and the ASP's own list shows the 32 never arrived. |
| _Dead end_ | Considered the API restarts (item 02) as the cause | Ruled out for Sahara. Their batch was submitted at 05:24:01Z, before the first OOM kill at 05:26:41Z. This is an independent defect. |

### Root cause

- **What happened:** The ERP pushed 40 invoices at once. Invoicely's submitter sent them to the ASP in parallel within ~0.1 s. The ASP accepted the first 8 (its fair-use burst) and answered **429 Too Many Requests** for the other 32. Invoicely has no handling for 429, so those 32 stay "Submitted" with no ASP reference, are never retried, and can't be retried by the customer.
- **Where:** `services/api/internal/submit/submit.go:133-155` (no `case http.StatusTooManyRequests`; no default branch). Also `submit.go:114` (status set to Submitted *before* the outcome is known) and `httpapi.go:270` / `store.go:368-370` (Retry excludes Submitted).
- **Why it happens:** The submitter was built for a "200/422/5xx" world. The ASP's documented 429 + `Retry-After` behaviour was never implemented, and there's no client-side rate limiting per sender.
- **Evidence:** Screenshots: [04-grafana-asp-429.png](evidence/04-grafana-asp-429.png) (HTTP 429 responses alongside 200s), [04-grafana-asp-outcome.png](evidence/04-grafana-asp-outcome.png) (ASP side: "throttled"; the small burst at ~10:54 IST is Sahara's batch), [04-portal-sahara-batch.png](evidence/04-portal-sahara-batch.png) (Sahara batch: "Submitted" with empty ASP reference). [q04-sahara.out.txt](evidence/q04-sahara.out.txt), [04-asp-received-sahara.txt](evidence/04-asp-received-sahara.txt) (ASP has 8/40), [04-asp-429-logs.txt](evidence/04-asp-429-logs.txt), [04-retry-blocked.txt](evidence/04-retry-blocked.txt) (409), [02-prometheus.txt](evidence/02-prometheus.txt) (throttled 595 = 595 stuck).
- **Confidence and open questions:** **Very high.** The ASP's own record proves the 32 were never received, so resubmitting them cannot create duplicates at the hospital.

### Customer resolution reply OR escalation note

- **Which one and why:** **Escalation to L3** (code defect plus a data repair support can't do: the 32 invoices must be moved out of "Submitted" and resent). I keep ownership of the Bluepeak/Sahara conversation.

**Update to Daniel (12:15):**

> Hi Daniel,
>
> Here's what I've found. It's a problem on our side, and I want to be completely clear about it.
>
> **1. Where are the rest of the invoices?**
> Of the 40 invoices in this morning's batch, **8 were delivered** (SMS-1116-001 to -008; these are the ones with an ASP reference). **The other 32 never left Invoicely.** They were not lost on the network or at the hospital's side. Our delivery partner limits how many invoices one sender can push per second. When your batch arrived all at once, it asked our system to slow down for the remaining 32, and our system didn't send them again as it should have. It also wrongly left them showing "Submitted". Your connector and your file did nothing wrong. The HTTP 201 was correct: the batch was received and validated.
>
> **2. Should you resend from the connector?**
> **Please don't.** It wouldn't create duplicates, but it wouldn't help either: the portal would reject the resent invoices because these numbers are already registered. The 32 invoices are safe in our system and will be sent from our side. I've confirmed with our delivery partner's records that none of the 32 has been received, so sending them once will not create duplicates at the hospital.
>
> **What happens next:** I've escalated this to our engineering team as a top priority. They'll release the 32 invoices and send them at a pace the network accepts, and fix the underlying problem. I've asked for this to be done this afternoon, and I'll check every one of the 32 has an ASP reference before I tell you it's done. If useful for Sahara's AR team: the 32 affected numbers are the batch's invoices without an ASP reference. I can send the exact list.
>
> Next update by 13:30.
>
> Best regards,
> Guru

**Escalation note:**

```markdown
### Escalation: ASP HTTP 429 not handled → invoices stuck in "Submitted" with no ASP ref, never retried (595 invoices, 5 sellers)

**Priority:** P1. Invoices silently not reaching the ASP; customer-visible status is wrong; Sahara's buyer payment run this week; Marina Bay (go-live Wed) has 143 affected.
**Customer / seller:** Sahara Medical Supplies FZE, seller_id 5 (via Bluepeak ERP connector). Also seller_id 1, 3, 7, 8.
**Reported by / at:** Daniel Okafor (Bluepeak), email, Mon 16 Nov 11:30
**Affected:** Import d176ba80-d2ab-419e-95ad-b57fe5ce9c82: 32 of 40 invoices Submitted, asp_message_id ''. Platform: 595 invoices (Palm Coast 143, Marina Bay 143, Zayed Port 140, Desert Rose 137, Sahara 32).

**Symptoms (customer view):** Status "Submitted", ASP reference empty; buyer never receives the invoice. Retry button → 409.

**Evidence:**
- ASP log: `"rate limit exceeded","sender":"0235:...","retry_after_s":1` (evidence/04-asp-429-logs.txt)
- API log: `"asp response" ... "status_code":429` and no later status change
- ASP record: GET /v1/documents?sender=0235:1006453719 → 8 documents (evidence/04-asp-received-sahara.txt)
- Metrics: asp_documents_total{outcome="throttled"} = 595; invoicely_asp_responses_total{code="429"}
- DB: `SELECT count(*) FROM invoices WHERE status='Submitted' AND asp_message_id='';` → 595
- Retry: POST /v1/invoices/{id}/retry → 409 (evidence/04-retry-blocked.txt)

**Steps to reproduce:** `make replay CUSTOMER=sahara` → 8 Accepted, 32 stuck Submitted.

**What I have already tried / ruled out:** Not buyer/Peppol registration (8 delivered to the same buyer). Not the OOM restarts (batch submitted before the first kill). Customer retry impossible (409). Told connector not to resend (would hit AE-BR-09 anyway).

**Suspected cause (very high confidence):** services/api/internal/submit/submit.go:133-155: switch has no case for 429 (and no default), so the invoice stays in Submitted (set at :114 before sending). Retry excludes Submitted (httpapi.go:270, store.go:368).

**Workaround in place:** No customer-side workaround. Customer told not to resend.

**Timeline:** 11:30 received · 11:40 ack · 11:50 ASP record shows 8/40 · 12:05 code cause found · 12:15 customer update

**Ask:**
1. **By 14:00 (data repair):** for the 595 invoices in Submitted with asp_message_id = '' (verified absent at the ASP), set status → Failed with detail "ASP rate limit (429) – not received" so they become retryable, then retry per seller at ≤ 2/s. I'll verify each gets an ASP reference. Sahara first (payment run), then Marina Bay.
2. **Code fix before Marina Bay go-live (Wed):** handle 429: honour Retry-After, requeue with backoff, keep status Validated (or a new "Queued") until the ASP answers; add a default branch → Failed; client-side per-sender rate limit (8 burst / 2 per s); allow Retry for Submitted older than N minutes with no ASP ref.
**Next customer update due:** 13:30
```

### Workaround offered

No customer-side workaround. The safe path is: don't resend (it would hit AE-BR-09); engineering moves the 32 invoices to a retryable state and resends them under the rate limit, and I verify each ASP reference. Longer term, a connector could pace its pushes, but the fix belongs on our side.

### Prevention ideas

- Implement the ASP's documented 429 + `Retry-After` contract, with a client-side per-sender rate limiter. Add a `default:` branch so no unknown status code can leave an invoice in limbo.
- Only mark "Submitted" once a request has actually been handed over, or add a "Queued/Throttled" status. Let Retry act on "Submitted with no ASP reference for more than 10 minutes".
- Daily reconciliation: compare the portal's Submitted/Accepted against the ASP's `GET /v1/documents?sender=` per seller.
- Alert on `increase(asp_documents_total{outcome="throttled"}[5m]) > 0` and on "invoices in Submitted > 5 min".
- Tell integration partners about the fair-use limit in the API docs.

---

## Incident 5 — `inbox/05-ghaf-cafe-date-error.md`

### Acknowledgement

- **Sent at (exercise clock):** 12:35 (received 12:10)
- **Reply:**

> Subject: RE: your system is broken - all my invoices rejected
>
> Dear Hessa,
>
> Thank you for getting in touch, and I'm sorry this has held up your invoices. I can see how frustrating it is when the date is clearly right.
>
> You're absolutely right that 13/11/2026 is the 13th of November. I've looked at your file, and I'm checking exactly how the dates need to be written so that I can give you a quick fix that works first time.
>
> I'll come back to you within the hour, by 13:30, with simple steps. Most likely just a small change to the date column in your Excel file, and then you can send all four invoices straight away.
>
> Kind regards,
> Guru
> Invoicely Lite Support

### Priority and justification

- **Priority:** **P3**
- **Why:** A single customer and a single issue, with a simple workaround. It's the product working as documented (AE-BR-04), so P4 would also be defensible. I chose P3 rather than P4 because the customer is **completely blocked** from invoicing (4 of 4 rejected) and is a small business with no accounts department, so getting her moving the same day matters. It's below the P1/P2 items because nothing is broken and nothing is lost: the invoices were rejected by the portal, not sent.
- **SLA deadlines I am working to:** First response by 16:10 (4 h; sent 12:35). Update daily. Resolution target 3 business days, aiming for today.

### Investigation log

| Time (exercise clock) | What I checked / did | What I found |
|---|---|---|
| 12:40 | DB: Ghaf invoices ([q05-ghaf.out.txt](evidence/q05-ghaf.out.txt)) | All 4 invoices Rejected **by portal** (never sent to the ASP), each with AE-BR-04 on `Invoice issue date*` and `Payment due date*`: `got '13/11/2026'`, `'13/12/2026'`, `'14/11/2026'` … |
| 12:45 | Inspected the file | The dates are stored as **text** strings `DD/MM/YYYY` in `xl/worksheets/sheet2.xml`, not as real Excel dates. |
| 12:48 | Docs: `docs/template-field-guide.md` → Dates; code [`sheet.go:171-186`](services/api/internal/sheet/sheet.go) (`ParseDate`) | Accepted: `YYYY-MM-DD` text, or real Excel date cells (serial numbers). `13/11/2026` as text is **rejected on purpose**: `05/11/2026` is 5 Nov in the UAE and 11 May in the US, and a tax invoice must never guess. **Working as documented.** |
| 12:55 | **Verified the fix**: changed only the date text to `YYYY-MM-DD` and uploaded ([05-fixed-file-upload.txt](evidence/05-fixed-file-upload.txt), file in [`evidence/files/`](evidence/files/)) | **4/4 Accepted** with ASP references, same invoice numbers (rejected invoices don't use up numbers). |
| _Considered_ | Should the portal accept DD/MM/YYYY because the seller is in the UAE? | Not an L1 decision, and the doc deliberately forbids guessing. Raised as a product suggestion (clearer message, template with a date-formatted column) rather than an incident. |

### Root cause

- **What happened:** The customer typed dates as text in the UAE format `13/11/2026`. The portal requires `YYYY-MM-DD` text or real Excel dates, and rejects ambiguous text dates with AE-BR-04.
- **Where:** `services/api/internal/sheet/sheet.go` → `ParseDate` (ISO regex or Excel serial only); `validate.go:113-119` raises AE-BR-04. Documented in `docs/template-field-guide.md` → Dates.
- **Why it happens:** By design, to prevent DD/MM vs MM/DD ambiguity on tax invoices. The error message says *what* format is needed but not *how* to get there in Excel, so to a non-accountant it reads as "your system is broken".
- **Evidence:** [q05-ghaf.out.txt](evidence/q05-ghaf.out.txt), [05-fixed-file-upload.txt](evidence/05-fixed-file-upload.txt) (corrected file → 4/4 Accepted).
- **Confidence and open questions:** **High.** No open questions.

### Customer resolution reply OR escalation note

- **Which one and why:** **Customer resolution reply. No escalation**: the product is working as documented (escalation policy: "Do not escalate when the product is working as documented"). I raised a UX improvement suggestion instead.

> Dear Hessa,
>
> Good news: I've found the cause, and it's a quick fix. Your invoices are all fine apart from how the dates are written.
>
> **What's happening:** your dates are correct. But in the file they're typed as text like 13/11/2026, and the portal needs them written year first: **2026-11-13**. That's because tax invoices go to customers all over the world, and a date like 05/11/2026 means 5 November here but 11 May in some other countries. The tax rules don't allow the system to guess, so it asks for one format that can only mean one thing. I'm sorry the error message didn't explain that better.
>
> **How to fix it (about 2 minutes):**
> 1. In your Excel file, change the dates in the **Invoice issue date** and **Payment due date** columns to the year-first format. For your four invoices:
>    - 13/11/2026 → **2026-11-13**
>    - 14/11/2026 → **2026-11-14**
>    - 15/11/2026 → **2026-11-15**
>    - and the due dates: 13/12/2026 → **2026-12-13**, 14/12/2026 → **2026-12-14**, 15/12/2026 → **2026-12-15**
> 2. Save the file and upload it again. You can use the **same invoice numbers**. Rejected invoices don't use them up.
>
> I tested your file with exactly this change on our side and all four invoices went through and were accepted.
>
> **For next time:** if you select the two date columns, choose *Format Cells → Custom* and type `yyyy-mm-dd`, then Excel will show and save dates the right way automatically.
>
> I'll check this afternoon that your four invoices show "Accepted". If anything doesn't go through, just reply to this email and I'll sort it out with you.
>
> Kind regards,
> Guru

### Workaround offered

Rewrite the dates as `YYYY-MM-DD` (or format the columns as real dates with `yyyy-mm-dd`) and upload again with the same invoice numbers. Verified: 4/4 Accepted.

### Prevention ideas

- Make the error more helpful: "Dates must be year-first, e.g. 2026-11-13 for 13 November. In Excel: Format Cells → Custom → yyyy-mm-dd" (and link to the field guide).
- Ship the template with the date columns pre-formatted as dates (`yyyy-mm-dd`) and data validation, so hand-typed entries become real dates.
- In the portal, show the interpreted date back ("we read 2026-11-13") before submission.
- A help-centre article on dates, linked from the AE-BR-04 message.

---

## Overall

### Prioritisation

**Order worked:** 02 → 01 → 04 → 03 → 05. Every item was acknowledged within its first-response target as it arrived (01 at 09:15, 02 at 09:52, 03 at 10:40, 04 at 11:40, 05 at 12:35).

- **09:05–09:50:** I started on **01 (Oasis)** because it was the only item in the queue: month-end, one customer, as P2.
- **09:50:** **02** (critical alert plus a CSM reporting multiple customers and a go-live) took over as the top priority. Production stability affects every customer, and the policy says page engineering on a P1 straight away. While investigating 02, I found the OOM kills also explained Oasis's 502 and its half-finished import, so I **raised 01 to P1** and worked them together.
- **11:30:** **04** jumped ahead of 03 even though it arrived later. I already suspected from the 02 metrics (595 "throttled") that invoices were silently not reaching the ASP, which is P1 and wider than one customer. It also changed my answer to Priya about Marina Bay: the restarts alone were fixable by raising memory, but the 429 problem would hit Marina Bay's go-live volume.
- **03 (P2):** I acknowledged it at 10:40, then investigated it in the late morning between P1 updates. It's a real defect with an auditor waiting, but only a subset of invoices is affected and nothing is lost.
- **05 (P3):** worked last, but the reply still went out within 25 minutes, and the fix was verified the same day, because it was quick and the customer was fully blocked.

**Did I change my mind?** Yes, twice. 01 went from P2 to P1 when it turned out to be part of the platform incident. And my first answer for Marina Bay would have been "OK once memory is raised". The Sahara investigation showed that would have been wrong, so I changed the recommendation to "conditional go-live after the 429 fix plus a full-volume test".

### What I would do differently

- **Check the ASP's own record earlier.** `GET /v1/documents?sender=` settled item 04 in one call and proved resending was safe. I'd make "compare our status with the ASP's record" a standard first step for any "not received" ticket.
- **Don't trust a single dashboard number.** "Submission queue = 0" looked healthy while 595 invoices were stuck, and `State.OOMKilled=false` looked like "not OOM" because Docker resets it on restart. I'd confirm from a second source (DB, kernel log) sooner.
- **Be careful when reproducing on a live system.** My Oasis repro triggered another OOM kill. In production I'd reproduce in staging, or after the memory mitigation.
- **Set a cadence reminder.** With three P1 threads open, I'd keep a written schedule of update times per customer, so the cadence never slips when an investigation gets interesting.

### What I learned / what I would need to learn

- **UAE e-invoicing / Peppol 5-corner model and PINT AE:** new to me. I learned it from `docs/architecture.md` and by reading the payload the portal builds (`pint.go`). The BR-CO rules (IBT-109/110/112) make sense once you see they're arithmetic identities between totals. Next: the full PINT AE specification and the FTA's rules on rounding and credit notes.
- **Linux OOM killer and cgroup limits:** I knew containers have memory limits, but not that `OOMKilled` is reset on restart, or that the definitive evidence is the kernel log (`Memory cgroup out of memory: Killed process …`). On Docker Desktop/WSL2 that log lives in the WSL VM's `dmesg`.
- **PromQL / Grafana / Loki:** I'd used dashboards before but not written queries. I learned `increase()`, `changes()`, `max_over_time()`, how to query the Prometheus HTTP API directly, and LogQL `{service="api"} | json`. Next: recording rules and writing alert rules for the gaps I found (memory near limit, throttling, stuck statuses).
- **Go service patterns:** how a background worker pool with an in-memory channel loses work on restart, and why durable queues or DB pollers exist. How a `switch` without a `default` can silently drop a case.
- **Rate limiting (token bucket) and HTTP 429 / Retry-After:** I understood the concept; this lab showed what happens when a client ignores it.
- **Support craft:** writing one explanation for three audiences (customer, auditor, engineer) at different depths.

### Time log (real time)

All times IST (UTC+5:30). Assignment email received on 13 Nov 2026 at about 18:30–19:00.

| Date | From–to | What I worked on |
|---|---|---|
| 13 Nov 2026 | 21:00–23:00 | Cloned the repo; read the assignment pack, `START_HERE.md`, `README.md`, the docs and the inbox; first priority read of the five items; started the environment set-up (`make` missing on Windows, so I moved to Ubuntu/WSL2) |
| 14 Nov 2026 | 10:00–11:15 | `make up`; baseline upload (Desert Rose) and Grafana walkthrough; `make load` and dashboard screenshot; code read-through (api, asp-mock, web proxy); investigation and evidence for 02, 04, 01 (reproduction), 03 and 05; writing and reviewing the replies, escalation notes and this document |

### AI usage disclosure

- **Tools used:** ChatGPT, Gemini, Claude/Claude Code, and GitHub Copilot/Copilot SDK in VS Code. I used them as assistants, not as sources of truth. Because Claude's free tier had a smaller usage limit, I used it selectively for quality-focused repository research and diagnosis so I could reserve that limited allowance for the highest-value reasoning. I then used Gemini and ChatGPT for additional research and rigorous cross-checking, and Copilot for output clarification and document formation.
- **What I did:** set up the environment (WSL2, Docker, `make up`), did the baseline upload and Grafana walkthrough, ran `make load`, took the dashboard screenshot, directed the investigation, and reviewed and edited the drafts. Final calls on priority, evidence interpretation, customer impact, and wording were mine.
- **What the tools did:** helped read and navigate the code and docs; suggested SQL, `curl`, Prometheus, Docker and `dmesg` checks; helped reproduce items 01 and 05; supported research on Peppol/PINT AE, PromQL, the OOM killer, Go worker queues, and HTTP 429 handling; and helped draft customer replies, escalation notes, and this write-up. I reviewed and adapted those suggestions rather than treating generated text or conclusions as verified work.
- **How I verified it:** Every factual claim in this document links to an evidence file produced by running a command against the local lab, not to an AI response. Key claims were checked from two independent sources:
  - OOM: kernel log plus Go heap metric.
  - Sahara: portal DB plus the ASP's own document list.
  - BR-CO-15: ASP error message plus an independent recalculation with exact decimals.
  - Ghaf fix: re-uploaded and checked 4/4 Accepted.

  The queries, scripts, evidence map, and reproducibility notes are in [`evidence/`](evidence/) so the results can be re-run and audited.
