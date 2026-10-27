import {openSectionScreen,closeSectionScreen} from './screen-navigation.js?v=3';
export function createCouponRewards({document,rpc,money,dates,canEdit,notify,run,openDetail,openProfile,onModeChange=()=>{},onGenerateCards,onLoadCards=async()=>{}}) {
 const $=id=>document.getElementById(id);
 let rows=[],epoch=0,saving=false,editingCode=null;
 const typeLabel=c=>c.reward_type==='free_ride'?'رحلة مجانية واحدة':'خصم بمبلغ';
 const node=(tag,value)=>{const e=document.createElement(tag);e.textContent=value;return e;};
 const action=(label,fn)=>{const e=node('button',label);e.type='button';e.className='secondary';e.onclick=()=>run(fn);return e;};
 const local=v=>{const d=new Date(v);return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16);};
 function mode(){const free=$('rewardType').value==='free_ride';$('rewardAmountField').hidden=free;$('rewardAmount').required=!free;$('rewardAmount').disabled=free||!canEdit()||saving;$('rewardExplanation').textContent=free?'رحلة واحدة مجانية لكل زبون. الكابتن يحصل على يوم اشتراك إضافي بعد إكمال الرحلة.':'يُطرح مبلغ الخصم من كروة الزبون؛ تُسجّل قيمة الخصم ضمن مستحقات الكابتن.';onModeChange({free,editing:editingCode!==null});}
 function reset(){ editingCode=null;$('rewardForm').reset();$('rewardCode').readOnly=false;$('rewardUses').value=100;$('rewardActive').checked=true;$('rewardExpiry').value=local(new Date(Date.now()+7*86400000));mode(); }
 function syncPermissions(){$('newRewardPage').disabled=!canEdit(); $('rewardForm').querySelectorAll('input,select,button').forEach(e=>e.disabled=!canEdit()||saving);mode(); }
 function render(){
  const list=$('rewardList');list.replaceChildren();const query=$('rewardSearch').value.trim().toUpperCase();
  for(const c of rows.filter(c=>c.code.includes(query))){
   const card=node('article','');card.className='record';card.append(node('h3',c.code),node('p',typeLabel(c)+' · '+(c.reward_type==='free_ride'?'كروة الزبون: 0 د.ع':money(c.amount))));
   for(const [label,value]of [['الحالة',!c.active?'متوقف':Date.parse(c.expires_at)<=Date.now()?'منتهي':'فعال'],['نهاية الصلاحية',dates(c.expires_at)],['الاستخدامات',`${c.uses} / ${c.max_uses}`],['الرحلات المكتملة',c.completed],['أيام اشتراك مُنحت للكباتن',c.bonus_days]])card.append(node('p',label+': '+value));
   const controls=node('div','');controls.className='controls';
   const edit=action('تعديل',async()=>{editingCode=c.code;$('rewardCode').value=c.code;$('rewardCode').readOnly=true;$('rewardType').value=c.reward_type||'amount';$('rewardAmount').value=c.amount;$('rewardExpiry').value=local(c.expires_at);$('rewardUses').value=c.max_uses;$('rewardActive').checked=c.active;mode();openSectionScreen($('rewardEditor'),'تعديل كود الخصم '+c.code);});edit.disabled=!canEdit();
   const stop=action('إيقاف الكود',async()=>{await rpc('stop',{code:c.code});await load();notify('تم إيقاف الكود مع حفظ السجل');});stop.disabled=!canEdit()||!c.active;
   controls.append(edit,action('سجل الرحلات والجوائز',()=>history(c)),stop);card.append(controls);list.append(card);
  }
  if(!list.children.length)list.append(node('p','لا توجد كودات مطابقة'));
 }
 async function history(c){
  const body=openDetail('سجل الكود '+c.code,{name:'couponHistory',args:[c.code]});let offset=0,pending=false;const list=node('div','');body.append(list);
  const more=action('تحميل المزيد',()=>loadNext());async function loadNext(){if(pending||!body.isConnected)return;pending=true;more.disabled=true;try{const data=await rpc('history',{code:c.code,offset});if(!body.isConnected)return;for(const r of data.rows){const item=node('article','');item.className='record';item.append(node('h3',r.customer_name||r.customer_phone),node('p','رقم الرحلة: '+r.id),node('p','الحالة: '+({pending:'قيد البحث',accepted:'الكابتن بالطريق',arrived:'وصل الكابتن',in_progress:'جارية',completed:'مكتملة',cancelled:'ملغية'}[r.status]||r.status)),node('p','المبلغ على الزبون: '+money(r.customer_due)),node('p','الخصم: '+money(r.discount)),node('p','الكابتن: '+(r.captain_name||'لم يُحدد')),node('p',r.days?'تم منح يوم اشتراك · ينتهي الاشتراك: '+dates(r.captain_expires_at):r.coupon_reward_type==='free_ride'?'يُمنح اليوم بعد إكمال الرحلة':'تعويض الخصم ضمن مستحقات الكابتن'),node('small',dates(r.created_at)));if(r.captain_id&&openProfile)item.append(action('عرض ملف الكابتن',()=>openProfile(r.captain_id)));list.append(item);}offset+=data.rows.length;more.hidden=data.rows.length<50;if(!offset)list.append(node('p','لم يُستخدم هذا الكود بعد'));}finally{pending=false;more.disabled=false;}}body.append(more);await loadNext();
 }
 async function load(){const current=++epoch;const data=await rpc('list');if(current!==epoch)return;rows=data.coupons;$('rewardSummary').textContent=`${rows.length} كود منفرد · ${data.free_completed} رحلة مجانية مكتملة · ${data.bonus_days} يوم اشتراك مُنح للكباتن`;render();syncPermissions();await onLoadCards();}
 $('newRewardPage').onclick=()=>{if(!canEdit())return;reset();openSectionScreen($('rewardEditor'),'إنشاء كود أو كارتات');};
 $('rewardType').onchange=mode;$('newReward').onclick=reset;$('rewardSearch').oninput=render;$('refreshRewards').onclick=()=>run(load);
 $('rewardForm').onsubmit=e=>{e.preventDefault();if(saving||!canEdit())return;run(async()=>{saving=true;syncPermissions();try{if($('rewardType').value==='free_ride'&&editingCode===null&&onGenerateCards){await onGenerateCards();await load();return;}await rpc('save',{code:$('rewardCode').value.trim().toUpperCase(),reward_type:$('rewardType').value,amount:$('rewardType').value==='free_ride'?100000:Number($('rewardAmount').value.replace(/[,٬\s]/g,'')),expires_at:new Date($('rewardExpiry').value).toISOString(),max_uses:Number($('rewardUses').value.replace(/[,٬\s]/g,'')),active:$('rewardActive').checked});await load();reset();closeSectionScreen($('rewardEditor'));notify('تم حفظ الكود وتفعيله بالتطبيق');}finally{saving=false;syncPermissions();}});};
 reset();return {load,syncPermissions,reset,async openHistory(code){const c=rows.find(c=>c.code===code);if(c)await history(c);},getState(){return editingCode?{code:editingCode}:null;},restore(state){const c=rows.find(c=>c.code===state.code);if(!c)return;editingCode=c.code;$('rewardCode').value=c.code;$('rewardCode').readOnly=true;$('rewardType').value=c.reward_type||'amount';$('rewardAmount').value=c.amount;$('rewardExpiry').value=local(c.expires_at);$('rewardUses').value=c.max_uses;$('rewardActive').checked=c.active;mode();}};
}
