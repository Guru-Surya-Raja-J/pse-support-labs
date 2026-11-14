\echo '== Sahara (seller 5) imports =='
SELECT id, filename, status, row_count, invoice_count, duration_ms, created_at FROM imports WHERE seller_id = 5 ORDER BY created_at;

\echo '== Sahara invoices by status and whether an ASP reference exists =='
SELECT status, (asp_message_id <> '') AS has_asp_ref, count(*) FROM invoices WHERE seller_id = 5 GROUP BY 1,2 ORDER BY 1;

\echo '== Status history of one stuck Sahara invoice (last event = Submitted, nothing after) =='
SELECT i.invoice_number, e.status, e.detail, e.created_at
FROM invoice_events e JOIN invoices i ON i.id = e.invoice_id
WHERE i.id = (SELECT id FROM invoices WHERE seller_id = 5 AND status = 'Submitted' ORDER BY invoice_number LIMIT 1)
ORDER BY e.id;

\echo '== Order in which Sahara invoices were submitted vs outcome (first 12 by submit time) =='
SELECT i.invoice_number, i.status, i.asp_message_id <> '' AS has_ref, min(e.created_at) FILTER (WHERE e.status='Submitted') AS submitted_at
FROM invoices i JOIN invoice_events e ON e.invoice_id = i.id
WHERE i.seller_id = 5 GROUP BY 1,2,3 ORDER BY 4 LIMIT 12;

\echo '== All sellers: invoices stuck in Submitted with no ASP reference (the 429 victims) =='
SELECT s.name, count(*) FROM invoices i JOIN sellers s ON s.id=i.seller_id
WHERE i.status='Submitted' AND i.asp_message_id='' GROUP BY 1 ORDER BY 2 DESC;
