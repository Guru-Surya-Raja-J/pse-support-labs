\echo '== Al Noor (seller 4) invoices: totals as sent, and outcome =='
SELECT invoice_number, status, rejected_by, total_excl_vat, total_vat, total_incl_vat,
       total_excl_vat + total_vat AS expected_incl, total_incl_vat - (total_excl_vat + total_vat) AS diff
FROM invoices WHERE seller_id = 4 ORDER BY created_at, invoice_number;

\echo '== Lines of the rejected invoices (qty x 3-decimal unit price) =='
SELECT i.invoice_number, l->>'id' AS line, (l->>'quantity')::numeric AS qty, (l->>'unitPrice')::numeric AS unit_price,
       (l->>'netAmount')::numeric AS net, (l->>'vatAmount')::numeric AS vat,
       round((l->>'quantity')::numeric * (l->>'unitPrice')::numeric, 4) AS qty_x_price_unrounded
FROM invoices i, jsonb_array_elements(i.payload->'lines') l
WHERE i.seller_id = 4 AND i.status = 'Rejected' ORDER BY 1,2;

\echo '== ASP rejection detail =='
SELECT invoice_number, errors->0->>'rule' AS rule, errors->0->>'message' AS message FROM invoices WHERE seller_id=4 AND status='Rejected';
