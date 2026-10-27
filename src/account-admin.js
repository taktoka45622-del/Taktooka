export function createAccountAdmin({document,rpc,invoke,openDetail,button,text,record,money,localPhone,run,notify,onDeleted,canManage}){
 const $=id=>document.getElementById(id);
 const types={owner:'مالك / مسؤول',staff:'موظف',captain:'كابتن',customer:'مستخدم',exchange:'صيرفة'};
 const errors={OWNER_REQUIRED:'حذف الحسابات متاح للمالك فقط',LAST_OWNER:'لا يمكن حذف آخر مالك فعال. أضف مالكًا آخر أولًا.',ACTIVE_RIDE:'أكمل أو ألغِ الرحلة الفعّالة أولًا.',ACTIVE_LINE:'أكمل أو ألغِ الخط الفعّال أولًا.',SETTLE_BALANCE:'صفّر رصيد المحفظة أو سدّد المستحقات أولًا.',SETTLE_EXCHANGE:'سوِّ رصيد الصيرفة ومستحقاتها أولًا.',ACCOUNT_CHANGED:'تغيّرت بيانات الحساب؛ افتح التأكيد مرة ثانية.',ACCOUNT_DELETED:'هذا الحساب محذوف مسبقًا.',ACCOUNT_NOT_FOUND:'الحساب غير موجود.',STORAGE_FAILED:'تعذّر حذف الملفات. أعد المحاولة لإكمال الحذف.',AUTH_DELETE_FAILED:'تعذّر إلغاء تسجيل الدخول. أعد المحاولة لإكمال الحذف.'};
 const errorMessage=e=>Object.entries(errors).find(([code])=>String(e?.message||e).includes(code))?.[1]||e?.message||'تعذّر الحذف؛ أعد المحاولة.';
 let sequence=0;
 async function load(){
  if(!canManage())return;const ticket=++sequence,list=$('accountAdminList');list.textContent='جاري تحميل الحسابات…';
  const rows=await rpc('list',{search:$('accountAdminSearch').value.trim(),type:$('accountAdminType').value});if(ticket!==sequence)return;
  list.replaceChildren();for(const row of rows||[]){const pending=['pending','purged'].includes(row.deletion_status);list.append(record(row.name||'حساب بدون اسم',[['الهاتف',localPhone(row.phone)||'—'],['نوع الحساب',types[row.account_type]||row.account_type],['الحالة',pending?'حذف غير مكتمل':row.blocked?'متوقف':'فعال']],[button(pending?'إكمال حذف الحساب':'حذف الحساب',()=>open(row.kind,row.id),'danger')]));}
  if(!rows?.length)list.append(text('p','لا توجد حسابات مطابقة.'));$('accountAdminCount').textContent=`${rows?.length||0} حساب · يعرض حتى 500 نتيجة؛ استخدم البحث لتحديد الحساب`;
 }
 async function open(kind,id){
  if(!canManage())throw new Error(errors.OWNER_REQUIRED);
  let info;try{info=await rpc('preview',{kind,id});}catch(e){throw new Error(errorMessage(e));}
  const body=openDetail('حذف الحساب نهائيًا',{name:'accountDelete',args:[kind,id]});
  body.append(record(info.name||'حساب بدون اسم',[['الهاتف',localPhone(info.phone)||'—'],['نوع الحساب',types[info.account_type]||info.account_type],['المحفظة',money(info.balance||0)],['رصيد الصيرفة',money(info.exchange_balance||0)],['مستحقات الصيرفة',money(info.exchange_due||0)]],[]));
  body.append(text('p','يحذف بيانات الحساب وملفاته ويمنع دخوله. تبقى سجلات الرحلات والأموال باسم «حساب محذوف». لا يمكن استرجاع الحساب.'));
  if(info.self)body.append(text('p','هذا حسابك الحالي؛ بعد اكتمال الحذف سيتم تسجيل خروجك.'));
  if(info.status==='completed'){body.append(text('p','تم حذف هذا الحساب مسبقًا.'));return;}
  const blockers=info.status==='ready'?info.blockers||[]:[];
  if(blockers.length){const note=text('div','');note.className='notice';note.setAttribute('role','alert');for(const code of blockers)note.append(text('p',errors[code]||code));body.append(note);return;}
  const form=document.createElement('form');form.className='account-delete-form';
  const label=text('label','اكتب كلمة حذف للتأكيد');label.className='field';const input=document.createElement('input');input.required=true;input.autocomplete='off';input.maxLength=10;input.setAttribute('aria-label','اكتب كلمة حذف للتأكيد');label.append(input);
  const checkLabel=text('label','');checkLabel.className='check-field';const check=document.createElement('input');check.type='checkbox';check.required=true;checkLabel.append(check,document.createTextNode('أؤكد حذف هذا الحساب نهائيًا'));
  const submit=text('button',info.status==='ready'?'حذف الحساب نهائيًا':'إكمال حذف الحساب');submit.type='submit';submit.className='danger';submit.disabled=true;
  const feedback=text('p','');feedback.setAttribute('role','status');let sending=false;
  const sync=()=>submit.disabled=sending||input.value.trim()!=='حذف'||!check.checked;input.oninput=sync;check.onchange=sync;
  form.onsubmit=e=>{e.preventDefault();if(sending||submit.disabled)return;run(async()=>{sending=true;sync();feedback.textContent='جاري حذف الحساب…';try{const result=await invoke({kind:info.kind,id:info.id,fingerprint:info.fingerprint,confirm:'DELETE_ACCOUNT'});feedback.textContent='تم حذف الحساب';await onDeleted(result);notify('تم حذف الحساب نهائيًا');}catch(e){feedback.textContent=errorMessage(e);throw new Error(feedback.textContent);}finally{sending=false;sync();}});};
  form.append(label,checkLabel,submit,feedback);body.append(form);
 }
 $('accountAdminSearchForm').onsubmit=e=>{e.preventDefault();run(load);};$('accountAdminType').onchange=()=>run(load);$('refreshAccounts').onclick=()=>run(load);
 return {load,open};
}
