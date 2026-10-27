export function englishDigits(value){return String(value??'').replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-0x660)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-0x6f0)).replace(/٬/g,',').replace(/٫/g,'.');}
export function clock12(hour,minute=0){return `${hour%12||12}:${String(minute).padStart(2,'0')} ${hour<12?'صباحًا':'مساءً'}`;}
export function displayClock(value){const match=englishDigits(value).match(/^(\d{1,2}):(\d{2})/);if(!match||+match[1]>23||+match[2]>59)return '—';return clock12(+match[1],+match[2]);}
export function displayTime(value){const d=new Date(value);if(!value||!Number.isFinite(d.getTime()))return '—';const parts=new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Baghdad',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(d);return clock12(+parts.find(p=>p.type==='hour').value,+parts.find(p=>p.type==='minute').value);}
export function displayDateTime(value){const d=new Date(value);if(!value||!Number.isFinite(d.getTime()))return '—';return new Intl.DateTimeFormat('ar-IQ-u-nu-latn',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(d)+' • '+displayTime(value);}
export function setupEnglishNumbers(root=document.body){
 const normalize=node=>{if(node.nodeType===Node.TEXT_NODE){const text=englishDigits(node.nodeValue);if(text!==node.nodeValue)node.nodeValue=text;}else if(node.nodeType===Node.ELEMENT_NODE&&!['SCRIPT','STYLE','TEXTAREA'].includes(node.tagName)){for(const child of node.childNodes)normalize(child);}};
 normalize(root);new MutationObserver(records=>{for(const r of records){if(r.type==='characterData')normalize(r.target);else r.addedNodes.forEach(normalize);}}).observe(root,{childList:true,characterData:true,subtree:true});
 root.addEventListener('input',e=>{const el=e.target;if(!['INPUT','TEXTAREA'].includes(el.tagName)||el.type==='password')return;const raw=el.value,value=englishDigits(raw);if(value!==raw){const start=el.selectionStart,end=el.selectionEnd;el.value=value;if(start!=null)el.setSelectionRange(start,end);}});
}

export function setupTwelveHourInputs(root=document){
 const originals=[...root.querySelectorAll('input[type="datetime-local"]'),...['night_start','night_end'].map(id=>root.getElementById(id)).filter(Boolean)];
 for(const original of originals){
  const dateTime=original.type==='datetime-local',descriptor=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value'),box=document.createElement('div');box.className='twelve-hour-editor';
  const date=document.createElement('input');date.type='date';date.lang='en-US';date.required=original.required;date.setAttribute('aria-label','التاريخ');
  const hour=document.createElement('select'),minute=document.createElement('select'),period=document.createElement('select');
  hour.setAttribute('aria-label','الساعة');minute.setAttribute('aria-label','الدقائق');period.setAttribute('aria-label','صباحًا أو مساءً');
  for(let n=1;n<=12;n++){const option=document.createElement('option');option.value=n;option.textContent=dateTime?String(n):`${n}:00`;hour.append(option);}
  for(let n=0;n<60;n++){const option=document.createElement('option');option.value=n;option.textContent=String(n).padStart(2,'0');minute.append(option);}
  for(const [value,label]of [['am','صباحًا'],['pm','مساءً']]){const option=document.createElement('option');option.value=value;option.textContent=label;period.append(option);}
  original.type='hidden';original.after(box);if(dateTime)box.append(date);box.append(hour);if(dateTime)box.append(minute);box.append(period);
  function sync(){const value=descriptor.get.call(original);let h=0,m=0;if(dateTime){const parts=value.split('T');date.value=parts[0]||'';const clock=(parts[1]||'00:00').split(':');h=+clock[0];m=+clock[1];}else h=Number(value)||0;hour.value=String(h%12||12);minute.value=String(m||0);period.value=h<12?'am':'pm';for(const el of [date,hour,minute,period])el.disabled=original.disabled;}
  Object.defineProperty(original,'value',{configurable:true,get(){return descriptor.get.call(this);},set(value){descriptor.set.call(this,value);sync();}});
  for(const el of [date,hour,minute,period])el.addEventListener('change',()=>{const h=Number(hour.value)%12+(period.value==='pm'?12:0),m=String(minute.value).padStart(2,'0');descriptor.set.call(original,dateTime?(date.value?`${date.value}T${String(h).padStart(2,'0')}:${m}`:''):String(h));original.dispatchEvent(new Event('change',{bubbles:true}));});
  new MutationObserver(sync).observe(original,{attributes:true,attributeFilter:['disabled']});original.form?.addEventListener('reset',()=>queueMicrotask(sync));sync();
 }
}

export function groupNumberInput(value){const raw=englishDigits(value).replaceAll(',','');if(!/^-?\d*(\.\d*)?$/.test(raw))return englishDigits(value);const [integer,decimal]=raw.split('.');const grouped=integer.replace(/(\d)(?=(\d{3})+(?!\d))/g,'$1,');return decimal===undefined?grouped:`${grouped}.${decimal}`;}
export function setupGroupedNumbers(root=document.body){
 function prepare(input){if(input.dataset.groupedNumbers)return;input.dataset.groupedNumbers='true';const descriptor=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value'),min=input.min,max=input.max,step=input.step;input.type='text';input.inputMode='decimal';
  function format(){const raw=descriptor.get.call(input),cursor=input.selectionStart,position=cursor==null?null:englishDigits(raw.slice(0,cursor)).replaceAll(',','').length,value=groupNumberInput(raw);descriptor.set.call(input,value);if(position!=null){let seen=0,index=0;while(index<value.length&&seen<position){if(value[index]!==',')seen++;index++;}input.setSelectionRange(index,index);}const n=Number(value.replaceAll(',',''));const invalid=value!==''&&(!/^-?\d+(\.\d+)?$/.test(value.replaceAll(',',''))||!Number.isFinite(n)||(min!==''&&n<Number(min))||(max!==''&&n>Number(max))||(step!==''&&step!=='any'&&Math.abs((n-Number(min||0))/Number(step)-Math.round((n-Number(min||0))/Number(step)))>1e-8));input.setCustomValidity(invalid?'أدخل رقمًا صحيحًا ضمن الحدود المحددة':'');}
  Object.defineProperty(input,'value',{configurable:true,get(){return englishDigits(descriptor.get.call(this)).replaceAll(',','');},set(value){descriptor.set.call(this,String(value??''));format();}});input.addEventListener('input',format);input.form?.addEventListener('reset',()=>queueMicrotask(format));format();
 }
 const scan=node=>{if(node.nodeType!==Node.ELEMENT_NODE)return;if(node.matches('input[type="number"]'))prepare(node);node.querySelectorAll('input[type="number"]').forEach(prepare);};scan(root);new MutationObserver(records=>records.forEach(r=>r.addedNodes.forEach(scan))).observe(root,{childList:true,subtree:true});
}
