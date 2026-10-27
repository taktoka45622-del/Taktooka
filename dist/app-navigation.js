export function createAppNavigation({key,capture,restore,notify,onRestoring=()=>{}}){
 let restoring=false,ready=false,exitAt=0,timer,depth=0,backPending=false,backInFlight=false,pendingPop=null,restoreQueue=Promise.resolve();
 const read=()=>{try{return JSON.parse(sessionStorage.getItem(key)||'null')}catch{return null}};
 const write=state=>{try{sessionStorage.setItem(key,JSON.stringify(state));}catch{}};
 const current=()=>({...capture(),savedAt:Date.now()});
 const arg=value=>value&&typeof value==='object'?(value.id||value.user_id||value.code||value.kind||null):value;
 const path=state=>JSON.stringify({page:state.page,sections:(state.sections||[]).map(s=>s.id),detail:state.detail?{name:state.detail.name,args:state.detail.name==='globalSearch'?[]:(state.detail.args||[]).map(arg)}:null,exchange:state.exchange?.id||null,account:state.exchange?.accountFilter||null,inventory:(state.sections||[]).some(s=>s.id==='inventoryDetails')?state.inventoryCategory:null,staff:state.staffUser||null});
 function save(){if(!ready||restoring||depth)return;const state=current(),old=history.state;if(old?.appKey===key&&!old.base&&path(old.snapshot||{})===path(state)){write(state);history.replaceState({...old,snapshot:state},'');}}
 function commit(replace=false){
  if(!ready||restoring||depth)return;
  const state=current(),old=history.state;write(state);
  const previous=old?.snapshot;
  if(!replace&&old?.appKey===key&&old.index>0&&previous?.page===state.page&&!state.detail&&((previous.detail&&JSON.stringify((previous.sections||[]).map(s=>s.id))===JSON.stringify((state.sections||[]).map(s=>s.id)))||(!previous.detail&&(previous.sections||[]).length>(state.sections||[]).length))){backInFlight=true;history.back();return;}
  if(replace||old?.appKey!==key||path(old.snapshot||{})===path(state))history.replaceState({appKey:key,index:old?.index||0,snapshot:state},'');
  else history.pushState({appKey:key,index:(old.index||0)+1,snapshot:state},'');
 }
 function begin(){if(!depth)save();depth++;}
 function end(){if(depth)depth--;if(!depth){if(pendingPop){const event=pendingPop;pendingPop=null;pop(event);return;}commit();if(backPending){backPending=false;back();}}}
 async function apply(state){
  restoring=true;onRestoring(true);try{await restore(state);await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));window.scrollTo({top:state.scroll||0,behavior:'instant'});for(const[id,top]of Object.entries(state.scrolls||{})){const el=document.getElementById(id);if(el)(el.closest?.('dialog.section-screen')||el).scrollTop=top;}if(state.focus){const el=document.getElementById(state.focus);if(el&&!el.closest('[hidden]'))el.focus({preventScroll:true});}}
  catch(e){notify('تعذّر استرجاع بعض التفاصيل؛ تم عرض آخر بيانات متاحة.');}
  finally{restoring=false;backInFlight=false;onRestoring(false);commit(true);}
 }
 function back(){if(!ready||restoring||backInFlight)return;if(depth){backPending=true;return;}save();backInFlight=true;history.back();}
 function pop(event){
  if(!ready)return;if(depth){pendingPop=event;backInFlight=true;return;}backInFlight=false;const state=event.state;
  if(state?.appKey===key&&!state.base){backInFlight=true;exitAt=0;restoreQueue=restoreQueue.then(()=>apply(state.snapshot));return;}
  if(Date.now()-exitAt<2200){ready=false;if(history.length<=2){window.close();setTimeout(()=>{ready=true;history.pushState({appKey:key,index:0,snapshot:read()||current()},'');notify('المتصفح يمنع إغلاق النافذة تلقائيًا؛ أغلقها من زر التطبيقات.');},300);}else history.back();return;}
  exitAt=Date.now();notify('اضغط رجوع مرة ثانية للخروج');history.pushState({appKey:key,index:0,snapshot:read()||current()},'');
 }
 const onBack=e=>{if(ready){e.detail.handled=true;back();}},onChange=e=>commit(Boolean(e.detail?.replace)),onSave=()=>save();
 const schedule=()=>{clearTimeout(timer);timer=setTimeout(save,120);};
 window.addEventListener('popstate',pop);window.addEventListener('tkt-navigation-back',onBack);window.addEventListener('tkt-navigation-change',onChange);window.addEventListener('tkt-navigation-save',onSave);window.addEventListener('pagehide',save);window.addEventListener('beforeunload',save);document.addEventListener('scroll',schedule,true);document.addEventListener('input',schedule,true);document.addEventListener('change',schedule,true);
 return{commit,back,save,begin,end,get restoring(){return restoring},async start(){
  history.scrollRestoration='manual';const snapshot=history.state?.appKey===key&&!history.state.base?history.state.snapshot:read();
  if(history.state?.appKey!==key){history.replaceState({appKey:key,base:true},'');history.pushState({appKey:key,index:0,snapshot:snapshot||current()},'');}
  ready=true;if(snapshot)await apply(snapshot);else commit(true);
 },clear(){ready=false;clearTimeout(timer);depth=0;backPending=false;try{sessionStorage.removeItem(key);}catch{}for(const[event,fn]of[['popstate',pop],['tkt-navigation-back',onBack],['tkt-navigation-change',onChange],['tkt-navigation-save',onSave],['pagehide',save],['beforeunload',save]])window.removeEventListener(event,fn);for(const event of ['scroll','input','change'])document.removeEventListener(event,schedule,true);}};
}
export function requestAppBack(fallback){const detail={handled:false};window.dispatchEvent(new CustomEvent('tkt-navigation-back',{detail}));if(!detail.handled)fallback?.();}
export function navigationChanged(replace=false){window.dispatchEvent(new CustomEvent('tkt-navigation-change',{detail:{replace}}));}
export function navigationWillChange(){window.dispatchEvent(new CustomEvent('tkt-navigation-save'));}
