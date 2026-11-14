\echo '== The morning replay of Rashid''s upload (make load, import 407a9872): 600 rows, 121.9 s, outcome per invoice =='
SELECT invoice_number, status, asp_message_id, total_incl_vat, updated_at FROM invoices
WHERE import_id = '407a9872-712d-4234-a99d-857e24b19940' ORDER BY invoice_number;
\echo '== Final state of my 3 portal-repro attempts =='
SELECT im.id, im.status, im.row_count, round(im.duration_ms/1000.0,1) secs,
  string_agg(i.status, ',' ORDER BY i.invoice_number) AS invoice_statuses
FROM imports im LEFT JOIN invoices i ON i.import_id = im.id
WHERE im.seller_id = 2 AND im.created_at > now() - interval '3 hours' GROUP BY 1,2,3,4,im.created_at ORDER BY im.created_at;
