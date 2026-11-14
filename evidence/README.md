# Evidence guide

This folder contains the supporting material for the investigation in
[`SUBMISSION.md`](../SUBMISSION.md). The files are grouped by incident number;
the SQL file immediately beside a query output is the query used to produce
that output.

## Evidence map

| Incident | Primary evidence | What it establishes |
|---|---|---|
| 01 Oasis | [`01-repro-portal-upload.txt`](01-repro-portal-upload.txt), [`q01-oasis-replay.out.txt`](q01-oasis-replay.out.txt), [`01-logs-repro.txt`](01-logs-repro.txt) | The portal times out while the server-side import continues, and repeated attempts can leave duplicate/rejected invoices. |
| 02 API restarts | [`02-oom-kills.txt`](02-oom-kills.txt), [`02-prometheus.txt`](02-prometheus.txt), [`02-api-log-before-restarts.txt`](02-api-log-before-restarts.txt) | The API container reaches its memory limit and is killed; in-memory work is interrupted. |
| 03 Al Noor | [`q03-al-noor.out.txt`](q03-al-noor.out.txt), [`03-br-co-15-worked-example.txt`](03-br-co-15-worked-example.txt) | The ASP rejection and independent arithmetic check agree on the rounding defect. |
| 04 Sahara | [`04-asp-429-logs.txt`](04-asp-429-logs.txt), [`q04-sahara.out.txt`](q04-sahara.out.txt), [`04-asp-received-sahara.txt`](04-asp-received-sahara.txt) | ASP rate limiting produced 429 responses; affected invoices remained without ASP references. |
| 05 Ghaf | [`q05-ghaf.out.txt`](q05-ghaf.out.txt), [`05-fixed-file-upload.txt`](05-fixed-file-upload.txt), [`files/ghaf-cafe-nov-2026-FIXED-dates.xlsx`](files/ghaf-cafe-nov-2026-FIXED-dates.xlsx) | The portal's date-format validation explains the rejection, and changing only the date text lets all four invoices be accepted. |

Screenshots are corroborating views of the portal and dashboards. The
timestamped text files are the more reproducible record because they preserve
the commands' relevant output. The sample workbook in `files/` is a derived
test fixture; only the date text was changed, as described in its companion
output file.

## Reproducibility and limits

- The outputs were captured from the local fictional lab during the real-time
  work recorded in the submission's time log.
- Times in service output are UTC; exercise-clock times in the submission are
  Asia/Dubai. They are separate clocks and should not be conflated.
- Re-running commands against a reset or newly loaded database will generate
  different UUIDs, timestamps, and possibly ordering. The claims are about the
  recorded run, not immutable production data.
- The evidence supports the conclusions stated in the submission; it is not a
  claim that every possible failure mode was tested.

## AI-assisted work

AI tools were used for repository orientation, research, drafting, and
clarifying documentation. The evidence itself was checked against the local
repository and the running lab. AI suggestions are not treated as evidence:
the commands, query outputs, application behavior, and code references are
the basis for the conclusions.
