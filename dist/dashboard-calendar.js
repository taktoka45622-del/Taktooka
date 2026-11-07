const form=document.getElementById('companyPeriodForm');
if(form){
 const from=document.getElementById('companyFrom'),to=document.getElementById('companyTo');
 const baghdadParts=new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());
 const part=type=>baghdadParts.find(p=>p.type===type).value;
 const today=new Date(Number(part('year')),Number(part('month'))-1,Number(part('day'))),dateKey=date=>`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
 let month=new Date(today.getFullYear(),today.getMonth(),1);
 const calendar=document.createElement('section');calendar.className='dashboard-calendar';calendar.setAttribute('aria-label','تقويم تقارير الشركة');
 const heading=document.createElement('div');heading.className='calendar-heading';
 const label=document.createElement('strong');label.id='dashboardCalendarMonth';label.setAttribute('aria-live','polite');
 const controls=document.createElement('div');controls.className='calendar-controls';
 function moveButton(text,title,step){const button=document.createElement('button');button.type='button';button.className='secondary';button.textContent=text;button.setAttribute('aria-label',title);button.onclick=()=>{month=new Date(month.getFullYear(),month.getMonth()+step,1);render();};return button;}
 controls.append(moveButton('‹','الشهر السابق',-1),moveButton('›','الشهر التالي',1));heading.append(label,controls);
 const weekdays=document.createElement('div');weekdays.className='calendar-weekdays';for(const name of ['سبت','أحد','إثنين','ثلاثاء','أربعاء','خميس','جمعة']){const day=document.createElement('span');day.textContent=name;weekdays.append(day);}
 const grid=document.createElement('div');grid.className='calendar-days';grid.setAttribute('role','group');grid.setAttribute('aria-labelledby',label.id);
 const note=document.createElement('small');note.textContent='اختر يومًا لعرض تقريره';calendar.append(heading,weekdays,grid,note);form.prepend(calendar);
 function render(){
  label.textContent=new Intl.DateTimeFormat('ar-IQ',{month:'long',year:'numeric'}).format(month);grid.replaceChildren();
  const offset=(month.getDay()+1)%7,days=new Date(month.getFullYear(),month.getMonth()+1,0).getDate();
  for(let i=0;i<offset;i++){const space=document.createElement('span');space.setAttribute('aria-hidden','true');grid.append(space);}
  for(let day=1;day<=days;day++){
   const date=new Date(month.getFullYear(),month.getMonth(),day),key=dateKey(date),button=document.createElement('button');
   button.type='button';button.className='secondary calendar-day';button.textContent=String(day);button.dataset.date=key;
   button.setAttribute('aria-label',new Intl.DateTimeFormat('ar-IQ',{dateStyle:'full'}).format(date));
   if(key===dateKey(today)){button.classList.add('today');button.setAttribute('aria-current','date');}
   const selected=Boolean(from.value&&to.value&&key>=from.value&&key<=to.value);button.classList.toggle('in-range',selected);button.setAttribute('aria-pressed',String(selected));button.disabled=key>dateKey(today);
   button.onclick=()=>{from.value=key;to.value=key;from.dispatchEvent(new Event('change',{bubbles:true}));to.dispatchEvent(new Event('change',{bubbles:true}));render();form.requestSubmit();};grid.append(button);
  }
 }
 from.addEventListener('change',render);to.addEventListener('change',render);form.addEventListener('submit',render);
 form.querySelectorAll('[data-company-range]').forEach(button=>button.addEventListener('click',()=>queueMicrotask(render)));
 new MutationObserver(render).observe(document.getElementById('page-company'),{attributes:true,attributeFilter:['hidden']});
 document.addEventListener('taktooka:surface-enter',event=>{if(event.detail?.surface?.contains(form))render();});
 render();
}
