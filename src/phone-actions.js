export function normalizeWhatsAppPhone(value){
 const digits=String(value||'').replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776)).replace(/[^0-9]/g,'');
 if(/^07[0-9]{9}$/.test(digits))return '964'+digits.slice(1);
 if(/^9647[0-9]{9}$/.test(digits))return digits;
 if(/^009647[0-9]{9}$/.test(digits))return digits.slice(2);
 return null;
}
export function whatsappUrl(value){const phone=normalizeWhatsAppPhone(value);return phone?'https://wa.me/'+phone:null;}
const ascii=value=>value.replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776));
const pattern=()=>/(?<![0-9A-Za-z])(?:\+?964|00964|0)[ -]*7(?:[ -]*[0-9]){9}(?![0-9A-Za-z])/g;
export function findPhoneNumbers(value){return [...ascii(String(value||'')).matchAll(pattern())].map(m=>({text:m[0],index:m.index,phone:normalizeWhatsAppPhone(m[0])})).filter(m=>m.phone);}
export function setupPhoneActions(document){
 const blocked='script,style,input,textarea,select,option,button,a,pre,code,.audit-details,.coupon-card-preview,[data-phone-contact],.leaflet-container';
 function link(phone){const a=document.createElement('a');a.href='https://wa.me/'+phone;a.target='_blank';a.rel='noopener noreferrer';a.className='whatsapp-link';a.dataset.phoneContact=phone;a.textContent='واتساب ↗';a.setAttribute('aria-label','فتح واتساب للرقم '+phone);a.title='فتح المحادثة في واتساب';return a;}
 function enhance(root){
  if(!root||root.nodeType!==1||root.closest(blocked))return;
  const conversations=[...(root.matches('.support-conversation')?[root]:[]),...root.querySelectorAll('.support-conversation')];
  for(const row of conversations){const open=row.querySelector('.conversation-open');if(!open)continue;const found=[...open.querySelectorAll('strong,span,small')].flatMap(node=>findPhoneNumbers(node.textContent))[0];if(found&&!row.querySelector('a.whatsapp-link'))row.append(link(found.phone));}
  const walker=document.createTreeWalker(root,4),nodes=[];let node;
  while((node=walker.nextNode()))if(node.parentElement&&!node.parentElement.closest(blocked)&&findPhoneNumbers(node.nodeValue).length)nodes.push(node);
  for(const node of nodes){
   const source=node.nodeValue,matches=findPhoneNumbers(source),fragment=document.createDocumentFragment();let at=0;
   for(const m of matches){fragment.append(document.createTextNode(source.slice(at,m.index)));const wrap=document.createElement('span');wrap.className='phone-contact';wrap.dataset.phoneContact=m.phone;const number=document.createElement('bdi');number.className='phone-number';number.textContent=m.text;wrap.append(number,link(m.phone));fragment.append(wrap);at=m.index+m.text.length;}
   fragment.append(document.createTextNode(source.slice(at)));node.replaceWith(fragment);
  }
 }
 let scheduled=false;const roots=new Set();
 function flush(){scheduled=false;const list=[...roots];roots.clear();for(const root of list)if(root.isConnected)enhance(root);}
 const observer=new MutationObserver(records=>{for(const record of records){const target=record.target.nodeType===1?record.target:record.target.parentElement;if(!target||target.closest(blocked))continue;if(record.type==='characterData')roots.add(target);else for(const n of record.addedNodes){if(n.nodeType===1&&!n.closest(blocked))roots.add(n);else if(n.nodeType===3)roots.add(target);}const conversation=target.closest('.support-conversation');if(conversation)roots.add(conversation);}if(roots.size&&!scheduled){scheduled=true;requestAnimationFrame(flush);}});
 enhance(document.body);observer.observe(document.body,{childList:true,subtree:true,characterData:true});
 return {refresh:()=>enhance(document.body),destroy:()=>observer.disconnect()};
}
