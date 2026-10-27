const categories={hosting:'السيرفر والاستضافة',maps:'الخرائط والخدمات',ads:'الإعلانات',salaries:'الرواتب',office:'مصاريف المكتب',other:'مصاريف أخرى'};
export function baghdadDay(now=new Date()){
 const parts=new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
 return ['year','month','day'].map(key=>parts.find(p=>p.type===key).value).join('-');
}
function shiftDay(day,offset){const d=new Date(day+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+offset);return d.toISOString().slice(0,10);}
export function companyIndicators(report){
 const revenue=Number(report.revenue||0),expenses=Number(report.expenses||0),previous=Number(report.previous_revenue||0),requested=Number(report.rides?.requested||0);
 return {revenue,expenses,net:revenue-expenses,growth:previous>0?Math.round((revenue-previous)/previous*1000)/10:null,
  completion:requested?Math.round(Number(report.rides.completed||0)/requested*1000)/10:0,
  cancellation:requested?Math.round(Number(report.rides.cancelled||0)/requested*1000)/10:0};
}
export function companyCsv(report){
 const value=companyIndicators(report),rows=[['تكتوكة — الشركة والأداء'],['من',report.from,'إلى',report.to],['ربح الاشتراكات',value.revenue],['المصاريف المسجلة',value.expenses],['الصافي بعد المصاريف المسجلة',value.net],['عدد دفعات الاشتراك',report.payments],['قيمة الاشتراك',report.fee],['أرصدة الزبائن — ليست ربح الشركة',report.wallets?.customer_funds||0],['أرصدة الكباتن — ليست ربح الشركة',report.wallets?.captain_funds||0],[],['اليوم','الاشتراكات','المصاريف المسجلة','الصافي']];
 for(const d of report.daily||[])rows.push([d.day,d.revenue,d.expenses,Number(d.revenue)-Number(d.expenses)]);
 return '\ufeff'+rows.map(row=>row.map(value=>'"'+String(value??'').replaceAll('"','""')+'"').join(',')).join('\r\n');
}
export function createCompanyPage({document,rpc,money,dates,canEdit,canOpenProfile,openProfile,confirmVoid}){
 const $=id=>document.getElementById(id),page=$('page-company');
 const text=(tag,value,cls)=>{const el=document.createElement(tag);el.textContent=String(value??'');if(cls)el.className=cls;return el;};
 const number=n=>new Intl.NumberFormat('en-US').format(Number(n||0));
 let report=null,rows=[],tab='payments',hasMore=false,sequence=0,rowSequence=0,loading=false,pendingExpense=null,lastSummaryAt=0;
 const today=baghdadDay();$('companyFrom').value=today.slice(0,8)+'01';$('companyTo').value=today;$('companyExpenseDate').value=today;for(const id of ['companyFrom','companyTo','companyExpenseDate'])$(id).max=today;
 function period(){return {from:$('companyFrom').value,to:$('companyTo').value};}
 function errorMessage(e){const raw=String(e?.message||e);if(raw.includes('INVALID_REPORT_PERIOD'))return 'حدد فترة صحيحة، لا تزيد عن سنة ولا تتجاوز اليوم.';if(raw.includes('INVALID_EXPENSE'))return 'راجع مبلغ المصروف وتاريخه ووصفه.';if(raw.includes('VOID_REASON_REQUIRED'))return 'اكتب سبب إلغاء المصروف.';if(raw.includes('PERMISSION_DENIED')||raw.includes('AUTH_REQUIRED'))return 'ما عندك صلاحية لعرض أو تعديل بيانات الشركة.';return 'تعذّر تحديث بيانات الشركة. حاول مرة ثانية.';}
 function notice(message='',error=false){$('companyStatus').textContent=message;$('companyStatus').classList.toggle('error',error);}
 function tile(container,label,value,caption,tone=''){const el=text('div','',`company-metric ${tone}`);el.append(text('span',label),text('strong',value),text('small',caption));container.append(el);}
 function profileButton(id){if(!canOpenProfile())return null;const b=text('button','عرض الملف الشخصي','secondary');b.type='button';b.onclick=()=>openProfile(id);return b;}
 function render(){
  const v=companyIndicators(report),p=report.profiles||{},r=report.rides||{},o=report.current_operations||{},l=report.lines||{};
  $('companyRevenue').textContent=money(v.revenue);$('companyPeriodLabel').textContent=`من ${report.from} إلى ${report.to} · بتوقيت بغداد`;
  $('companyGrowth').textContent=v.growth===null?'الفترة السابقة بلا إيرادات اشتراك':`${v.growth>0?'+':''}${number(v.growth)}% مقارنة بالفترة السابقة (${report.previous_from} — ${report.previous_to})`;
  const finances=$('companyFinancials');finances.replaceChildren();
  tile(finances,'المصاريف المسجلة',money(v.expenses),'المصاريف غير الملغية خلال الفترة','red');
  tile(finances,'الصافي بعد المصاريف المسجلة',money(v.net),'يتغير حسب المصاريف التي تسجلها هنا',v.net<0?'red':'green');
  tile(finances,'دفعات الاشتراك',number(report.payments),`كل دفعة ${money(report.fee)}`);
  tile(finances,'كباتن دفعوا خلال الفترة',number(report.paying_captains),'عدد الكباتن المختلفين، بدون تكرار التجديدات');
  tile(finances,'كباتن اشتركوا لأول مرة',number(report.first_paid_captains),'أول دفعة مسجلة لكل كابتن');
  tile(finances,'إجمالي ربح الاشتراكات منذ البداية',money(report.lifetime_revenue),'كل الدفعات المسجلة، قبل المصاريف','green');
  const operations=$('companyOperations');operations.replaceChildren();
  const metrics=[['طلبات الفترة',r.requested,'حسب تاريخ إنشاء الطلب'],['الرحلات المكتملة',r.completed,`${number(v.completion)}% من طلبات الفترة`],['الرحلات الملغية',r.cancelled,`${number(v.cancellation)}% من طلبات الفترة`],['زبائن استفادوا من رحلات مكتملة',r.customers_served,'عدد الزبائن المختلفين خلال الفترة'],['كباتن نفّذوا رحلات',r.captains_worked,'رحلات مكتملة ضمن طلبات الفترة'],['حسابات زبائن جديدة',p.new_customers,'حسابات أُنشئت خلال الفترة'],['اشتراكات فعالة الآن',p.active,'حسب تاريخ انتهاء الاشتراك'],['اشتراكات منتهية الآن',p.expired,'كباتن لديهم اشتراك سابق'],['كباتن لم يشتركوا',p.never,'لم يُحدد لهم اشتراك بعد'],['متصلون بموقع حديث',p.online_fresh,'غير محظورين، اشتراك فعال وموقع خلال 15 ثانية'],['رحلات جارية الآن',o.running,'تشمل الطلبات التي تبحث عن كابتن'],['طلبات تنتظر كابتن الآن',o.pending,'الحالة الحالية لكل الطلبات'],['خطوط مستلمة الآن',l.active,'خطوط قبلها الكابتن'],['خطوط تنتظر القبول',l.pending,'خطوط جديدة لم يستلمها كابتن']];
  for(const [label,value,caption]of metrics)tile(operations,label,number(value),caption);
  $('companyCustomerFunds').textContent=money(report.wallets?.customer_funds||0);$('companyCaptainFunds').textContent=money(report.wallets?.captain_funds||0);$('companyRideFares').textContent=money(r.completed_fares||0);
  const alerts=$('companyAlerts');alerts.replaceChildren();
  const items=[p.expiring_soon?`${number(p.expiring_soon)} اشتراك ينتهي خلال 3 أيام. فرصة تجديد بقيمة ${money(p.expiring_soon*report.fee)} إذا جدد الجميع؛ هذا مبلغ محتمل وغير محصّل.`:'ماكو اشتراكات تنتهي خلال 3 أيام.',o.long_wait?`${number(o.long_wait)} طلب ينتظر كابتن منذ أكثر من 10 دقائق.`:'ماكو طلب ينتظر أكثر من 10 دقائق.',v.cancellation>=25&&r.requested>=5?`نسبة الإلغاء ${number(v.cancellation)}%. راجع توفر الكباتن ومناطق الخدمة.`:`نسبة إلغاء طلبات الفترة ${number(v.cancellation)}%.`];
  for(const item of items)alerts.append(text('p',item,'company-alert'));
  const expiring=$('companyExpiring');expiring.replaceChildren();
  for(const c of report.expiring||[]){const row=text('div','', 'company-expiring-row');row.append(text('strong',c.name||'كابتن'),text('span',c.phone||''),text('small',`ينتهي ${dates(c.expires_at)}`));const b=profileButton(c.user_id);if(b)row.append(b);expiring.append(row);}
  if(!report.expiring?.length)expiring.append(text('p','لا توجد اشتراكات تحتاج متابعة قريبة.'));
  renderChart();$('companyUpdated').textContent='آخر تحديث: '+dates(report.server_now);$('companyExport').disabled=false;syncPermissions();
 }
 function renderChart(){
  const chart=$('companyChart'),daily=report.daily||[],group=Math.max(1,Math.ceil(daily.length/35)),buckets=[];chart.replaceChildren();
  for(let i=0;i<daily.length;i+=group){const entries=daily.slice(i,i+group);buckets.push({from:entries[0].day,to:entries.at(-1).day,revenue:entries.reduce((s,d)=>s+Number(d.revenue),0),expenses:entries.reduce((s,d)=>s+Number(d.expenses),0)});}
  const maximum=Math.max(1,...buckets.flatMap(b=>[b.revenue,b.expenses]));
  for(const b of buckets){const column=text('div','', 'company-chart-column');column.tabIndex=0;const label=`${b.from}${b.to!==b.from?' — '+b.to:''}: الاشتراكات ${money(b.revenue)}، المصاريف ${money(b.expenses)}`;column.title=label;column.onclick=()=>{$('companyChartCaption').textContent=label;};column.setAttribute('aria-label',label);const bars=text('div','', 'company-bars');for(const [key,cls]of [['revenue','income'],['expenses','expense']]){const bar=text('span','',`company-bar ${cls}`);bar.style.height=`${b[key]?Math.max(2,b[key]/maximum*100):0}%`;bars.append(bar);}column.append(bars,text('small',b.from.slice(5)));chart.append(column);}
  $('companyChartCaption').textContent=group===1?'كل عمود يمثل يومًا. مرّر المؤشر أو اختر العمود لمعرفة المبلغ.':`كل عمود يجمع حتى ${group} أيام؛ التقرير المُصدّر يحتوي تفاصيل كل يوم.`;
 }
 function renderRows(){
  const list=$('companyRecords');list.replaceChildren();
  for(const row of rows){const el=text('article','', 'company-record');
   if(tab==='payments'){
    el.append(text('strong',row.name||'كابتن'),text('b',money(row.amount),'company-record-money'),text('span',row.phone||''),text('small',`تاريخ الدفعة: ${dates(row.created_at)}`),text('small',`نهاية الاشتراك بعد الدفعة: ${dates(row.expires_at)}`),text('small',`استلم الدفعة: ${row.received_by||'الإدارة'}`));const b=profileButton(row.captain_id);if(b)el.append(b);
   }else{
    el.classList.toggle('voided',Boolean(row.voided_at));el.append(text('strong',row.description),text('b',money(row.amount),'company-record-money'),text('span',categories[row.category]||row.category),text('small',`تاريخ المصروف: ${row.spent_on}`),text('small',`سجّله: ${row.created_by_name||'الإدارة'}`),text('small',`تاريخ التسجيل: ${dates(row.created_at)}`));
    if(row.voided_at)el.append(text('small',`ملغى — ${row.void_reason||''} · ${row.voided_by_name||'الإدارة'} · ${dates(row.voided_at)}`));
    else if(canEdit()){const b=text('button','إلغاء المصروف','secondary');b.type='button';b.onclick=async()=>{const reason=confirmVoid();if(!reason?.trim())return;b.disabled=true;try{await rpc('expense_void',{id:row.id,reason:reason.trim()});const refreshed=await load();notice(refreshed?'تم إلغاء المصروف وحفظ السبب في السجل.':'تم إلغاء المصروف، لكن تعذّر تحديث التقرير. اضغط تحديث البيانات.',!refreshed);}catch(e){notice(errorMessage(e),true);}finally{b.disabled=false;}};el.append(b);}
   }list.append(el);
  }
  if(!rows.length)list.append(text('p',tab==='payments'?'ماكو دفعات اشتراك مسجلة خلال هذه الفترة.':'ماكو مصاريف مسجلة خلال هذه الفترة.','company-empty'));
  $('companyMore').hidden=!hasMore;$('companyRecordsPeriod').textContent=report?`سجل الفترة ${report.from} — ${report.to} · ${number(rows.length)} سجل ظاهر`:'';
  page.querySelectorAll('[data-company-tab]').forEach(b=>{b.classList.toggle('selected',b.dataset.companyTab===tab);b.setAttribute('aria-pressed',String(b.dataset.companyTab===tab));});
 }
 async function load({summaryOnly=false}={}){
  if(summaryOnly&&(!report||loading||Date.now()-lastSummaryAt<60000))return;const token=++sequence,rowsToken=summaryOnly?rowSequence:++rowSequence,range=summaryOnly?{from:report.from,to:report.to}:period(),signature=JSON.stringify(range);loading=true;$('companyRefresh').disabled=true;notice();
  try{
   const [data,items]=await Promise.all([rpc('report',range),summaryOnly?Promise.resolve(null):rpc(tab,{...range,offset:0})]);
   if(token!==sequence||(!summaryOnly&&signature!==JSON.stringify(period())))return false;report=data;lastSummaryAt=Date.now();render();if(items&&rowsToken===rowSequence){rows=items.items||[];hasMore=Boolean(items.has_more);renderRows();}return true;
  }catch(e){if(token===sequence)notice(errorMessage(e),true);return false;}finally{if(token===sequence){loading=false;$('companyRefresh').disabled=false;}}
 }
 async function loadMore(){if(!report||loading)return;const token=++rowSequence,currentTab=tab,range={from:report.from,to:report.to},offset=rows.length;$('companyMore').disabled=true;try{const result=await rpc(tab,{...range,offset});if(token!==rowSequence||currentTab!==tab)return;rows.push(...result.items||[]);hasMore=Boolean(result.has_more);renderRows();}catch(e){notice(errorMessage(e),true);}finally{$('companyMore').disabled=false;}}
 function syncPermissions(){const form=$('companyExpenseForm');form.querySelectorAll('input,select,button').forEach(el=>el.disabled=!canEdit());$('companyExpensePermission').textContent=canEdit()?'تسجيل المصروف يحدث صافي الربح ويحفظ اسم المسؤول.':'صلاحيتك عرض فقط؛ تسجيل المصاريف يحتاج صلاحية تعديل المحافظ والأكواد.';}
 $('companyPeriodForm').onsubmit=e=>{e.preventDefault();load();};$('companyRefresh').onclick=()=>load();$('companyMore').onclick=loadMore;
 page.querySelectorAll('[data-company-range]').forEach(b=>b.onclick=()=>{const end=baghdadDay();$('companyTo').value=end;$('companyFrom').value=b.dataset.companyRange==='month'?end.slice(0,8)+'01':shiftDay(end,-Number(b.dataset.companyRange)+1);load();});
 page.querySelectorAll('[data-company-tab]').forEach(b=>b.onclick=()=>{tab=b.dataset.companyTab;rows=[];hasMore=false;renderRows();load();});
 $('companyExport').onclick=()=>{if(!report)return;const url=URL.createObjectURL(new Blob([companyCsv(report)],{type:'text/csv;charset=utf-8'}));const a=text('a','');a.href=url;a.download=`Taktooka-Company-${report.from}-${report.to}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
 $('companyExpenseForm').onsubmit=async e=>{
  e.preventDefault();if(!canEdit())return;const values={spent_on:$('companyExpenseDate').value,amount:Number($('companyExpenseAmount').value.replaceAll(',','')),category:$('companyExpenseCategory').value,description:$('companyExpenseDescription').value.trim()},signature=JSON.stringify(values);
  if(!Number.isSafeInteger(values.amount)||values.amount<=0){notice('أدخل مبلغ مصروف صحيحًا.',true);return;}
  if(pendingExpense?.signature!==signature)pendingExpense={signature,id:crypto.randomUUID()};const submit=$('companyExpenseSave');if(submit.disabled)return;submit.disabled=true;
  try{await rpc('expense_add',{...values,id:pendingExpense.id});pendingExpense=null;$('companyExpenseAmount').value='';$('companyExpenseDescription').value='';const refreshed=await load();notice(refreshed?(values.spent_on<report.from||values.spent_on>report.to?'تم تسجيل المصروف خارج الفترة المعروضة.':'تم تسجيل المصروف وتحديث صافي الربح.'):'تم تسجيل المصروف، لكن تعذّر تحديث التقرير. اضغط تحديث البيانات.',!refreshed);}catch(err){notice(errorMessage(err),true);}finally{submit.disabled=!canEdit();}
 };
 function reset(){sequence++;rowSequence++;loading=false;report=null;rows=[];pendingExpense=null;for(const id of ['companyFinancials','companyOperations','companyChart','companyAlerts','companyExpiring','companyRecords'])$(id).replaceChildren();for(const id of ['companyRevenue','companyCustomerFunds','companyCaptainFunds','companyRideFares'])$(id).textContent='—';for(const id of ['companyGrowth','companyPeriodLabel','companyUpdated','companyRecordsPeriod','companyStatus'])$(id).textContent='';$('companyExport').disabled=true;$('companyExpenseAmount').value='';$('companyExpenseDescription').value='';}
 return {load,syncPermissions,reset,cancel(){sequence++;rowSequence++;loading=false;$('companyRefresh').disabled=false;},getReport:()=>report};
}
