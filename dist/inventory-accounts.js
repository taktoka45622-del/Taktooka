import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.95.3';
import { inventoryFinanceSpecs, inventoryFinanceValue, inventoryFinanceRows } from './inventory-finance-model.js';

const client = createClient('https://typbkzwbrmkrfkfxjrgi.supabase.co', 'sb_publishable_Oto-5IRPHgWceHq_uzrsiw_JBBZbAOT', { auth: { storageKey: 'taktooka-web-admin' } });
const formatDate = value => {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '—' : new Intl.DateTimeFormat('ar-IQ', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Baghdad' }).format(date);
};
const money = value => new Intl.NumberFormat('en-US').format(Number(value) || 0) + ' د.ع';
const count = value => new Intl.NumberFormat('en-US').format(Number(value) || 0);
const field = (label, value) => [label, value == null || value === '' ? '—' : String(value)];

function node(tag, value, className) {
  const element = document.createElement(tag);
  if (value != null) element.textContent = String(value);
  if (className) element.className = className;
  return element;
}

function phoneDigits(value) {
  return String(value || '').replace(/[٠-٩]/g, char => String(char.charCodeAt(0) - 0x660)).replace(/\D/g, '');
}

function detailsFor(item, category) {
  const fields = {
    completed_rides: [field('رقم الرحلة', item.id), field('الزبون', item.customer_name), field('هاتف الزبون', item.customer_phone), field('الكابتن', item.captain_name), field('هاتف الكابتن', item.captain_phone), field('الانطلاق', item.pickup_name), field('الوصول', item.destination_name), field('الكروة', money(item.fare)), field('تاريخ الإكمال', formatDate(item.updated_at))],
    completed_food_orders: [field('رقم الطلب', item.id), field('المطعم', item.restaurant_name), field('هاتف المطعم', item.restaurant_phone), field('الزبون', item.customer_name), field('هاتف الزبون', item.customer_phone), field('المندوب', item.captain_name), field('هاتف المندوب', item.captain_phone), field('الطعام', money(item.food_total)), field('التوصيل', money(item.delivery_fee)), field('رسوم الخدمة', money(item.service_fee)), field('عمولة الشركة', money(item.commission_amount)), field('وقت التسليم', formatDate(item.updated_at))],
    captains_weekly: [field('الاسم', item.name), field('الهاتف', item.phone), field('نوع الاشتراك', 'أسبوعي'), field('المركبة', item.vehicle), field('الاشتراك ينتهي', formatDate(item.expires_at)), field('آخر رحلة', formatDate(item.last_ride_at))],
    captains_commission: [field('الاسم', item.name), field('الهاتف', item.phone), field('النظام', 'نسبة على الطلبات'), field('المركبة', item.vehicle), field('آخر رحلة', formatDate(item.last_ride_at))],
    captains_no_ride_2d: [field('الاسم', item.name), field('الهاتف', item.phone), field('النظام', item.plan === 'commission' ? 'نسبة' : 'اشتراك أسبوعي'), field('المركبة', item.vehicle), field('آخر رحلة مسجلة', formatDate(item.last_ride_at)), field('تاريخ التسجيل', formatDate(item.created_at))],
    restaurant_service_due: [field('اسم المطعم / الحساب', item.name), field('هاتف المطعم', item.phone), field('اسم صاحب المطعم', item.owner_name), field('هاتف صاحب المطعم', item.owner_phone), field('العنوان', item.address), field('الرصيد المستحق', money(item.amount)), field('عدد القيود', count(item.debt_count)), field('آخر قيد', formatDate(item.last_debt_at)), ...(item.legacy_unlinked ? [field('ملاحظة', 'قيد مالي سابق بقي محفوظًا بعد حذف سجل المطعم؛ الاسم المعروض هو حساب المالك')]:[])],
    taxi_commission_due: [field('الكابتن', item.captain_name), field('هاتف الكابتن', item.captain_phone), field('العمولة', money(item.amount)), field('مرجع الرحلة', item.source_id), field('مسار الرحلة', item.source_label), field('تاريخ الرحلة', formatDate(item.source_created_at)), field('تاريخ احتساب العمولة', formatDate(item.created_at))],
    food_commission_due: [field('الكابتن', item.captain_name), field('هاتف الكابتن', item.captain_phone), field('العمولة', money(item.amount)), field('رقم طلب الطعام', item.source_id), field('تاريخ الطلب', formatDate(item.source_created_at)), field('تاريخ احتساب العمولة', formatDate(item.created_at))],
    exchange_funds: [field('اسم الصيرفة', item.name), field('هاتف الصيرفة', item.phone), field('صاحب الصيرفة', item.personal_name), field('هاتف صاحب الصيرفة', item.personal_phone), field('المحافظة', item.province), field('المنطقة', item.area), field('العنوان', item.street), field('الرصيد المخزون', money(item.balance)), field('الحالة', item.active ? 'فعالة' : 'متوقفة'), field('تاريخ التسجيل', formatDate(item.created_at))],
    company_profit: [field('النوع', item.kind), field('الجهة', item.person_name), field('هاتف التواصل', item.person_phone), field('التفاصيل', item.details), field('المبلغ المسجل', money(item.amount)), field('التاريخ', formatDate(item.created_at)), field('المرجع', item.id)]
  };
  return fields[category] || [field('التفاصيل', JSON.stringify(item))];
}

function titleFor(item, category) {
  if (category === 'completed_rides') return `${item.pickup_name || 'الانطلاق'} ← ${item.destination_name || 'الوصول'}`;
  if (category === 'completed_food_orders') return item.restaurant_name || 'طلب طعام مكتمل';
  if (category === 'restaurant_service_due') return item.name || 'حساب مطعم';
  if (category === 'taxi_commission_due' || category === 'food_commission_due') return item.captain_name || 'كابتن';
  if (category === 'exchange_funds') return item.name || 'صيرفة';
  if (category === 'company_profit') return item.kind || 'حركة مالية';
  return item.name || 'كابتن';
}

function createInventoryAccounts() {
  const page = document.getElementById('page-inventory');
  const sourceGrid = document.getElementById('inventoryCards');
  if (!page || !sourceGrid || document.getElementById('inventoryFinanceCards')) return null;

  const section = node('section', null, 'inventory-finance-section');
  section.setAttribute('aria-label', 'مؤشرات إضافية وحسابات الشركة');
  const heading = node('div', null, 'row section-heading');
  const headingCopy = node('div');
  headingCopy.append(node('span', 'متابعة الأرباح والأرصدة', 'eyebrow'), node('h2', 'المجاميع المالية والتشغيلية'));
  const refresh = node('button', 'تحديث البيانات', 'secondary');
  refresh.type = 'button';
  heading.append(headingCopy, refresh);
  const status = node('p', '');
  status.className = 'inventory-finance-status';
  status.setAttribute('role', 'status');
  const grid = node('div', null, 'inventory-finance-grid');
  grid.id = 'inventoryFinanceCards';
  section.append(heading, status, grid);
  sourceGrid.insertAdjacentElement('afterend', section);

  const dialog = node('dialog', null, 'inventory-finance-dialog');
  dialog.setAttribute('aria-labelledby', 'inventoryFinanceTitle');
  const head = node('div', null, 'inventory-finance-dialog-head');
  const titleGroup = node('div');
  titleGroup.append(node('span', 'كشف الحسابات', 'eyebrow'));
  const title = node('h2', '', '');
  title.id = 'inventoryFinanceTitle';
  titleGroup.append(title);
  const close = node('button', 'إغلاق', 'secondary');
  close.type = 'button';
  close.onclick = () => dialog.close();
  head.append(titleGroup, close);
  const body = node('div', null, 'inventory-finance-dialog-body');
  const description = node('p', '', 'inventory-finance-description');
  const toolbar = node('form', null, 'inventory-finance-toolbar');
  const searchLabel = node('label', 'بحث بالاسم أو الهاتف أو المرجع', 'field');
  const search = node('input');
  search.type = 'search';
  search.placeholder = 'اكتب كلمة للبحث';
  searchLabel.append(search);
  const searchButton = node('button', 'بحث');
  toolbar.append(searchLabel, searchButton);
  const callout = node('div', null, 'inventory-finance-callout');
  const rows = node('div', null, 'inventory-finance-rows');
  const footer = node('div', null, 'inventory-finance-dialog-footer');
  const openAccounting = node('button', 'متابعة التسديد والتصفير', 'secondary');
  openAccounting.type = 'button';
  openAccounting.hidden = true;
  openAccounting.onclick = () => {
    const target = document.querySelector(`[data-page="${currentCategory === 'exchange_funds' ? 'exchanges' : 'commerce'}"]`);
    if (target && !target.hidden) { dialog.close(); target.click(); }
  };
  const more = node('button', 'عرض سجلات أكثر', 'secondary');
  more.type = 'button';
  footer.append(openAccounting, more);
  body.append(description, toolbar, callout, rows, footer);
  dialog.append(head, body);
  document.body.append(dialog);

  let summary = null;
  let currentCategory = '';
  let currentOffset = 0;
  let hasMore = false;
  let loadedRows = [];
  let listRequest = 0;
  let summaryRequest = 0;
  const values = new Map();

  async function rpc(action, data = {}) {
    const { data: result, error } = await client.rpc('tkt_finance_inventory', { p_action: action, p_data: data });
    if (error) throw error;
    return result;
  }

  function drawCards() {
    if (!summary) return;
    grid.replaceChildren();
    for (const spec of inventoryFinanceSpecs) {
      const tile = node('button', null, `inventory-tile inventory-finance-tile`);
      tile.type = 'button';
      tile.dataset.tone = spec.tone;
      tile.setAttribute('aria-label', `${spec.label}: ${inventoryFinanceValue(spec, summary[spec.key])}، عرض التفاصيل`);
      tile.append(node('span', spec.icon, 'inventory-icon'), node('span', spec.label, 'inventory-label'), node('strong', inventoryFinanceValue(spec, summary[spec.key]), `inventory-value${spec.type === 'money' ? ' money-value' : ''}`), node('span', 'عرض التفاصيل ←', 'inventory-open'));
      tile.onclick = () => openCategory(spec);
      grid.append(tile);
    }
  }

  function renderRows(items) {
    rows.replaceChildren();
    for (const item of inventoryFinanceRows(items, currentCategory)) {
      const article = node('article', null, 'inventory-finance-row record');
      article.append(node('h3', titleFor(item, currentCategory)));
      const facts = node('dl', null, 'inventory-finance-facts');
      for (const [label, value] of detailsFor(item, currentCategory)) {
        const wrapper = node('div');
        wrapper.append(node('dt', label), node('dd', value));
        facts.append(wrapper);
      }
      article.append(facts);
      const contacts = currentCategory === 'restaurant_service_due'
        ? [['اتصال بالمطعم', item.phone], ['اتصال بصاحب المطعم', item.owner_phone]]
        : [['اتصال', item.phone || item.captain_phone || item.customer_phone || item.restaurant_phone || item.person_phone || item.personal_phone]];
      if (contacts.some(([, value]) => value)) {
        const actions = node('div', null, 'controls inventory-finance-contact');
        for (const [label, contactPhone] of contacts) {
          if (!contactPhone) continue;
          const tel = node('a', label);
          tel.href = `tel:${contactPhone}`;
          tel.className = 'secondary';
          actions.append(tel);
          const digits = phoneDigits(contactPhone);
          if (digits.length >= 10) {
            const wa = node('a', `واتساب · ${label.replace('اتصال ', '')}`);
            wa.href = `https://wa.me/${digits.startsWith('0') ? `964${digits.slice(1)}` : digits}`;
            wa.target = '_blank';
            wa.rel = 'noopener';
            wa.className = 'secondary';
            actions.append(wa);
          }
        }
        article.append(actions);
      }
      rows.append(article);
    }
    if (!items.length) rows.append(node('p', 'ماكو سجلات مطابقة حاليًا.', 'inventory-finance-empty'));
  }

  async function loadRows(reset = true) {
    const request = ++listRequest;
    if (reset) { currentOffset = 0; loadedRows = []; }
    rows.replaceChildren(node('p', 'جاري تحميل التفاصيل…', 'inventory-finance-empty'));
    try {
      const result = await rpc('rows', { category: currentCategory, search: search.value.trim(), limit: 30, offset: currentOffset });
      if (request !== listRequest || !dialog.open) return;
      const items = result.rows || [];
      hasMore = Boolean(result.has_more);
      currentOffset += items.length;
      loadedRows = reset ? items : [...loadedRows, ...items];
      more.hidden = !hasMore;
      renderRows(loadedRows);
      description.textContent = `${inventoryFinanceSpecs.find(spec => spec.key === currentCategory)?.description || ''} · ${count(result.total)} سجل`;
    } catch (error) {
      if (request !== listRequest || !dialog.open) return;
      more.hidden = true;
      rows.replaceChildren(node('p', error?.message || 'تعذر تحميل التفاصيل؛ أعد المحاولة.', 'inventory-finance-empty'));
    }
  }

  async function openCategory(spec) {
    currentCategory = spec.key;
    title.textContent = spec.label;
    search.value = '';
    callout.replaceChildren();
    const accountingTarget = document.querySelector(`[data-page="${spec.key === 'exchange_funds' ? 'exchanges' : 'commerce'}"]`);
    openAccounting.hidden = !['restaurant_service_due', 'taxi_commission_due', 'food_commission_due', 'exchange_funds'].includes(spec.key) || !accountingTarget || accountingTarget.hidden;
    if (summary) callout.append(node('strong', inventoryFinanceValue(spec, summary[spec.key]), 'inventory-finance-total'));
    if (spec.key === 'restaurant_service_due') callout.append(node('span', 'اضغط متابعة التسديد والتصفير لفتح سجلات التسديد الحالية وإجراءات اعتماد الاستلام.'));
    if (['taxi_commission_due', 'food_commission_due'].includes(spec.key)) callout.append(node('span', 'إجراءات تأكيد التسديد متاحة من صفحة النسب ورسوم الخدمة.'));
    if (spec.key === 'exchange_funds') callout.append(node('span', 'فتح الصيرفات يعرض الحسابات والمعاملات وسجل التسديد.'));
    if (!dialog.open) dialog.showModal();
    await loadRows(true);
  }

  async function loadSummary() {
    const request = ++summaryRequest;
    refresh.disabled = true;
    status.textContent = 'جاري تحديث المؤشرات…';
    try {
      const result = await rpc('summary');
      if (request !== summaryRequest) return;
      summary = result;
      drawCards();
      status.textContent = `آخر تحديث: ${formatDate(result.server_now)}`;
      if (dialog.open && currentCategory) {
        const spec = inventoryFinanceSpecs.find(item => item.key === currentCategory);
        callout.replaceChildren(node('strong', inventoryFinanceValue(spec, summary[currentCategory]), 'inventory-finance-total'));
      }
    } catch (error) {
      if (request === summaryRequest) status.textContent = error?.message || 'تعذر تحديث المؤشرات؛ أعد المحاولة.';
    } finally {
      refresh.disabled = false;
    }
  }

  refresh.onclick = () => loadSummary();
  toolbar.onsubmit = event => { event.preventDefault(); loadRows(true); };
  more.onclick = () => loadRows(false);
  dialog.addEventListener('close', () => { listRequest++; rows.replaceChildren(); });
  new MutationObserver(() => {
    if (!page.hidden) loadSummary();
    else if (dialog.open) dialog.close();
  }).observe(page, { attributes: true, attributeFilter: ['hidden'] });
  if (!page.hidden) loadSummary();
  return { refresh: loadSummary };
}

createInventoryAccounts();
