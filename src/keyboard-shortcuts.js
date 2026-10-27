
export function setupKeyboardShortcuts({document,window,menu,notifications,help,onSearch=()=>{},notify=()=>{}}){
 const chatIds=new Set(['chatInput','exchangeReply','messageBody','recoveryBody']);
 const editable=el=>el?.matches?.('input,textarea,select,[contenteditable="true"]');
 const visible=el=>el&&!el.disabled&&el.getClientRects().length>0&&!el.closest('[hidden],[inert]');
 const submit=form=>{if(!form)return false;const buttons=[...form.elements].filter(el=>el.type==='submit'||el.type==='image');const button=buttons.find(visible);if(buttons.length&&!button)return false;form.requestSubmit(button);return true;};
 let panel=null;
 function showHelp(){if(!panel){panel=document.createElement('dialog');panel.className='keyboard-help';panel.setAttribute('aria-label','اختصارات الكيبورد');const title=document.createElement('h2');title.textContent='اختصارات الكيبورد';panel.append(title);for(const[key,description]of[['Enter','إرسال رسالة الدعم أو تنفيذ الحقل الحالي'],['Shift + Enter','سطر جديد داخل رسالة الدعم'],['Ctrl + Enter','إرسال النموذج الحالي'],['Ctrl + K','الانتقال إلى البحث بالصفحة الحالية'],['Alt + M','فتح أو إغلاق القائمة الجانبية'],['Alt + N','فتح الإشعارات'],['Alt + ←','الرجوع للصفحة السابقة'],['Esc','الرجوع من المحادثة أو إغلاق النافذة'],['Tab / Shift + Tab','التنقّل بين الحقول والأزرار'],['Ctrl + /','عرض هذه الاختصارات']]){const row=document.createElement('p'),code=document.createElement('kbd');code.textContent=key;row.append(code,document.createTextNode(' — '+description));panel.append(row);}const close=document.createElement('button');close.type='button';close.textContent='تمام';close.onclick=()=>panel.close();panel.append(close);document.body.append(panel);}if(!panel.open)panel.showModal();}
 if(help){help.onclick=showHelp;help.setAttribute('aria-keyshortcuts','Control+/');}
 menu?.setAttribute('aria-keyshortcuts','Alt+M');notifications?.setAttribute('aria-keyshortcuts','Alt+N');
 const handler=event=>{
 if(event.defaultPrevented||event.isComposing||event.keyCode===229)return;
 const target=event.target,mod=event.ctrlKey||event.metaKey,key=event.key.toLowerCase();
 if(mod&&key==='/'&&!event.altKey){event.preventDefault();if(!event.repeat)showHelp();return;}
 if(event.key==='Enter'&&!event.altKey&&!event.shiftKey&&chatIds.has(target.id)){event.preventDefault();if(!event.repeat)submit(target.form);return;}
 if(mod&&event.key==='Enter'&&!event.shiftKey&&!event.altKey){event.preventDefault();if(!event.repeat)submit(target.form||target.closest('form'));return;}
 if(event.key==='Enter'&&!mod&&!event.altKey&&!event.shiftKey&&target.tagName==='INPUT'){
 if(onSearch(target.id)){event.preventDefault();return;}
 if(!target.form){const scope=target.closest('dialog[open]');if(scope){const button=[...scope.querySelectorAll('button')].find(b=>visible(b)&&/^(حفظ|تأكيد|بحث|دخول|إرسال|إنشاء)/.test(b.textContent.trim()));if(button){event.preventDefault();if(!event.repeat)button.click();}}}return;
 }
 if(mod&&key==='k'&&!event.altKey){event.preventDefault();const scope=document.activeElement?.closest('dialog[open]')||document.querySelector('.chat-screen:not([hidden]),.agent-chat-screen:not([hidden])')||document.querySelector('.page:not([hidden])')||document;const search=[...scope.querySelectorAll('input[type="search"],input[id$="Search"],input[id$="search"]')].find(visible);if(search){search.focus();search.select();}else notify('هذه الصفحة ما بيها حقل بحث.');return;}
 if(event.altKey&&!mod&&!event.shiftKey&&(key==='m'||key==='n')){if(editable(target))return;const button=key==='m'?menu:notifications;if(visible(button)){event.preventDefault();if(!event.repeat)button.click();}}
 };
 document.addEventListener('keydown',handler);
 return{showHelp,destroy(){document.removeEventListener('keydown',handler);panel?.remove();}};
}
