\echo '== Ghaf Tree Cafe (seller 6) invoices and portal errors =='
SELECT i.invoice_number, i.status, i.rejected_by, e->>'rule' AS rule, e->>'row' AS row, e->>'message' AS message
FROM invoices i, jsonb_array_elements(i.errors) e WHERE i.seller_id = 6 ORDER BY 1, 5;
