export function createCommercePage({document,rpc,money,canEdit,run,profile,phone}) {
 const $=id=>document.getElementById(id);
 const text=(tag,value)=>{const e=document.createElement(tag);e.textContent=String(value??'');return e;};
 const names={restaurant_fee:'رسوم الخدمة لدى المطعم',captain_company:'عمولة الشركة لدى الكابتن',captain_restaurant:'مستحقات المطعم لدى الكابتن'};
 let busy=false;
 async function load(){
  const data=await rpc('admin');
  for(const key of ['commission_percent','service_fee','captain_debt_limit','restaurant_debt_limit']){$('commerce_'+key).value=data.settings[key];$('commerce_'+key).disabled=!canEdit('finance');}
  $('commerceSave').disabled=!canEdit('finance');
  const totals={};for(const d of data.debts)totals[d.kind]=(totals[d.kind]||0)+d.amount;
  $('commerceTotals').replaceChildren(...Object.entries(names).map(([key,label])=>text('p',`${label}: ${money(totals[key]||0)}`)));
  const people=new Map();for(const d of data.debts){const key=d.debtor_id+':'+d.kind;const x=people.get(key)||{...d,amount:0};x.amount+=d.amount;people.set(key,x);}
  $('commerceDebts').replaceChildren(...[...people.values()].map(d=>{const row=text('article','');row.className='record';row.append(text('strong',d.name),text('p',`${phone(d.phone)} · ${names[d.kind]} · ${money(d.amount)}`));const button=text('button','عرض الحساب');button.onclick=()=>run(()=>profile(d.debtor_id));row.append(button);return row;}));
  $('commerceSettlements').replaceChildren(...data.settlements.map(s=>{
   const row=text('article','');row.className='record';row.append(text('strong',names[s.kind]),text('p',`${money(s.amount)} · ${s.created_at}`));
   const detail=data.debts.find(d=>d.debtor_id===s.debtor_id);if(detail)row.append(text('p',`${detail.name} · ${phone(detail.phone)}`));
   if(s.kind!=='captain_restaurant'){const b=text('button','تأكيد استلام المبلغ وتصفير هذه الدفعة');b.disabled=!canEdit('finance');b.onclick=()=>run(async()=>{if(busy)return;if(!confirm(`تأكيد استلام ${money(s.amount)} فعلياً؟ سيتم تسديد المبالغ المشمولة بهذا الطلب فقط.`))return;busy=true;b.disabled=true;try{await rpc('settlement_confirm',{id:s.id,confirmed_amount:s.amount});await load();}finally{busy=false;b.disabled=!canEdit('finance');}});row.append(b);}
   else row.append(text('p','يُؤكد بكود من المطعم يُدخله الكابتن.'));
   return row;
  }));
 }
 $('commerceForm').onsubmit=e=>{e.preventDefault();run(async()=>{const data={};for(const key of ['commission_percent','service_fee','captain_debt_limit','restaurant_debt_limit'])data[key]=Number($('commerce_'+key).value);await rpc('settings_save',data);await load();});};
 $('commerceRefresh').onclick=()=>run(load);
 async function complaints(){
  const rows=await rpc('complaints');$('restaurantComplaints').replaceChildren(...rows.map(c=>{const row=text('article','');row.className='record';row.append(text('strong',`${c.restaurant_name} — ${c.captain_name}`),text('p',phone(c.captain_phone)),text('p',c.body),text('small',c.status==='handled'?'تم التعامل':'جديدة'));if(c.status==='open'){const b=text('button','تم التعامل');b.disabled=!canEdit('support');b.onclick=()=>run(async()=>{await rpc('complaint_handle',{id:c.id});await complaints();});row.append(b);}return row;}));
 }
 return {load,complaints};
}
