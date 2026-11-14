\echo '== Oasis (seller 2) imports, newest last =='
SELECT id, filename, status, row_count, invoice_count, round(duration_ms/1000.0,1) AS secs, created_at, completed_at
FROM imports WHERE seller_id = 2 ORDER BY created_at;

\echo '== Oasis invoices from the real file (OBS-2611-xxx), per import =='
SELECT i.import_id, i.invoice_number, i.status, i.rejected_by, left(i.errors->0->>'message', 95) AS first_error, i.asp_message_id <> '' AS has_asp_ref
FROM invoices i WHERE i.seller_id = 2 AND i.invoice_number NOT LIKE '%-H8BN%'
ORDER BY i.created_at, i.invoice_number;

\echo '== Which Oasis November invoices actually reached the ASP (answer to the customer question 1) =='
SELECT invoice_number, status, asp_message_id FROM invoices
WHERE seller_id = 2 AND asp_message_id <> '' AND invoice_number NOT LIKE '%-H8BN%' ORDER BY 1;
