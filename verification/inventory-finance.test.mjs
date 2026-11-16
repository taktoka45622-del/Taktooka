import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { inventoryFinanceSpecs, inventoryFinanceRows, inventoryFinanceValue } from '../src/inventory-finance-model.js';

const expected = [
  'completed_food_orders',
  'captains_weekly',
  'captains_commission',
  'captains_no_ride_2d',
  'restaurant_service_due',
  'taxi_commission_due',
  'food_commission_due',
  'exchange_funds',
  'company_profit'
];
assert.deepEqual(inventoryFinanceSpecs.map(spec => spec.key), expected);
assert.equal(inventoryFinanceValue(inventoryFinanceSpecs[0], 1234), '1,234');
assert.equal(inventoryFinanceValue(inventoryFinanceSpecs.find(spec => spec.key === 'company_profit'), 1234), '1,234 د.ع');
assert.equal(inventoryFinanceValue(inventoryFinanceSpecs.find(spec => spec.key === 'company_profit'), -500), '-500 د.ع');
assert.deepEqual(inventoryFinanceRows([{ id: 'a' }], 'completed_food_orders'), [{ id: 'a', category: 'completed_food_orders' }]);
assert.deepEqual(inventoryFinanceRows(null, 'completed_food_orders'), []);

const ui = await readFile(new URL('../src/inventory-accounts.js', import.meta.url), 'utf8');
const sql = await readFile(new URL('../supabase/taktooka/inventory_finance.sql', import.meta.url), 'utf8');
const css = await readFile(new URL('../src/inventory-accounts.css', import.meta.url), 'utf8');
for (const text of ['tkt_finance_inventory', 'showModal()', 'inventoryFinanceCards', 'واتساب', 'متابعة التسديد والتصفير', 'اسم صاحب المطعم', 'item.owner_phone', 'formatDate(result.server_now)', 'receipt_preview', 'record_receipt', 'تسجيل الاستلام وتصفير المستحق', 'المبلغ المستلم فعليًا']) assert.ok(ui.includes(text), `missing UI behavior: ${text}`);
for (const text of ['receipt_preview', 'record_receipt', 'commerce_settlements', 'commerce_settlement_items', "'commerce_receipt'", "v_amount<>v_due"]) assert.ok(sql.includes(text), `missing settlement behavior: ${text}`);
for (const text of ["status='delivered'", "cp.plan='commission'", "interval '48 hours'", "d.kind='restaurant_fee'", 'max(p.name) owner_name', 'max(p.phone) owner_phone', "exists(select 1 from public.tkt_rides r where r.id=d.source_id)", "exists(select 1 from tkt_private.food_orders f where f.id=d.source_id)", 'tkt_private.company_expenses']) assert.ok(sql.includes(text), `missing server calculation: ${text}`);
assert.ok(css.includes('.inventory-finance-dialog::backdrop'));
assert.ok(css.includes('@media(max-width:700px)'));
console.log('Inventory finance dashboard checks passed.');
