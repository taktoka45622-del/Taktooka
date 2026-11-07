const paths={company:'M3 3h7v7H3z M14 3h7v11h-7z M3 14h7v7H3z M14 18h7',lines:'M4 7h16m-4-4 4 4-4 4M20 17H4m4-4-4 4 4 4',inventory:'M3 3h18v18H3zM3 9h18M9 9v12M15 9v12',staff:'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M17 4a4 4 0 0 1 0 8M22 21v-2a4 4 0 0 0-3-4',exchanges:'M3 6h18M5 3v18M19 3v18M3 18h18M9 9h6v6H9z',overview:'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8',wheel:'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18M12 3v18M3 12h18M6 6l12 12M6 18 18 6',banners:'M3 3h18v18H3zM3 17l6-6 4 4 3-3 5 5M16 7h.01',pricing:'M4 6h16M4 12h16M4 18h16M8 3v6M16 9v6M10 15v6',rides:'M4 8h16l2 7H2l2-7zM5 8l2-5h10l2 5M5 15v5M19 15v5M6 12h.01M18 12h.01',applications:'M6 3h12v18H6zM9 7h6M9 11h6M9 15h4',users:'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M17 4a4 4 0 0 1 0 8',coverage:'M12 21s7-7 7-12A7 7 0 0 0 5 9c0 5 7 12 7 12zM12 6a3 3 0 1 0 0 6 3 3 0 0 0 0-6',commerce:'M4 20 20 4M7 3a3 3 0 1 0 0 6 3 3 0 0 0 0-6M17 15a3 3 0 1 0 0 6 3 3 0 0 0 0-6','restaurant-support':'M4 3v7a3 3 0 0 0 6 0V3M7 3v18M20 21V3c-4 2-5 8 0 9',finance:'M3 5h18v15H3zM3 5V3h14M15 10h6v5h-6z',rewards:'M3 8h18v4a3 3 0 0 0 0 6v3H3v-3a3 3 0 0 0 0-6V8zM12 8v13',support:'M4 14v-3a8 8 0 0 1 16 0v3M4 11H2v7h5v-7H4M20 11h2v7h-5v-7h3M20 18v3h-6',favorites:'m12 3 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z',security:'m12 2 9 4v6c0 6-9 10-9 10S3 18 3 12V6l9-4zM8 12l3 3 5-6',audit:'M5 3h14v18H5zM8 7h8M8 12h8M8 17h5',server:'M3 3h18v7H3zM3 14h18v7H3zM7 6h.01M7 17h.01'};
function icon(name){const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('fill','none');svg.setAttribute('stroke','currentColor');svg.setAttribute('stroke-width','1.6');svg.setAttribute('stroke-linecap','round');svg.setAttribute('stroke-linejoin','round');svg.setAttribute('aria-hidden','true');const path=document.createElementNS(svg.namespaceURI,'path');path.setAttribute('d',paths[name]||paths.company);svg.append(path);return svg;}
const rail=document.createElement('nav');rail.className='dashboard-rail';rail.setAttribute('aria-label','أقسام تكتوكة');
const brand=document.createElement('button');brand.type='button';brand.className='rail-brand';brand.textContent='ت';brand.setAttribute('aria-label','فتح قائمة تكتوكة');brand.title='قائمة تكتوكة';brand.onclick=()=>document.getElementById('menuToggle').click();rail.append(brand);
const links=document.createElement('div');links.className='rail-links';rail.append(links);const pairs=[];
for(const source of document.querySelectorAll('#navigation button[data-page]')){const item=document.createElement('button');item.type='button';item.append(icon(source.dataset.page));item.title=source.textContent;item.setAttribute('aria-label',source.textContent);item.onclick=()=>source.click();links.append(item);pairs.push([source,item]);}
document.body.append(rail);
const header=document.querySelector('header.topbar'),tools=header.querySelector('.header-actions');
const toolsButton=document.createElement('button');toolsButton.type='button';toolsButton.className='dashboard-tools-button';toolsButton.textContent='•••';toolsButton.setAttribute('aria-label','أدوات الإدارة');toolsButton.setAttribute('aria-expanded','false');tools.id='dashboardTools';toolsButton.setAttribute('aria-controls',tools.id);tools.hidden=true;header.append(toolsButton);
function closeTools(){tools.hidden=true;toolsButton.setAttribute('aria-expanded','false');}
toolsButton.onclick=()=>{const open=tools.hidden;tools.hidden=!open;toolsButton.setAttribute('aria-expanded',String(open));};
document.addEventListener('click',event=>{if(!tools.contains(event.target)&&!toolsButton.contains(event.target))closeTools();});document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!tools.hidden){closeTools();toolsButton.focus();}});
const reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
let signed=false,introAnimation;
const rollTimers=new Map();
function play(node,frames,options){if(!node.animate)return null;const animation=node.animate(frames,options);return animation;}
function stopIntro(){introAnimation?.cancel?.();introAnimation=null;document.querySelector('.dashboard-intro')?.remove();document.body.classList.remove('dashboard-entering');}
function intro(){
 if(reduced.matches)return;stopIntro();const cover=document.createElement('div');cover.className='dashboard-intro';cover.setAttribute('aria-hidden','true');const logo=document.createElement('div');logo.className='intro-logo';logo.innerHTML='<b>ت</b><strong>تكتوكة</strong><small>لوحة الإدارة</small>';cover.append(logo);document.body.append(cover);
 introAnimation=play(cover,[{opacity:1},{opacity:0}],{duration:220,easing:'ease-out',fill:'forwards'});
 if(introAnimation?.finished)introAnimation.finished.then(()=>{stopIntro();const page=document.querySelector('.page:not([hidden])');if(page)enterPage(page);}).catch(()=>{});else stopIntro();
}
function rollNumbers(page){
 for(const node of page.querySelectorAll('.company-metric strong,.company-hero>strong,.metric>strong,.inventory-value')){
  if(node.querySelector('.number-roll'))continue;const raw=node.textContent,match=raw.match(/^(\s*)([\d,]+(?:\.\d+)?)(.*)$/s);if(!match)continue;const end=Number(match[2].replaceAll(',',''));if(!Number.isFinite(end)||end<=0)continue;
  const reel=document.createElement('span');reel.className='number-roll';reel.setAttribute('aria-hidden','true');const precision=match[2].includes('.')?match[2].split('.')[1].length:0;
  for(let i=0;i<9;i++){const line=document.createElement('span');line.textContent=i===8?raw:match[1]+new Intl.NumberFormat('en-US',{maximumFractionDigits:precision}).format(Math.floor(end*i/8))+match[3];reel.append(line);}
  node.classList.add('rolling-value');node.append(reel);const cleanup=()=>{reel.remove();node.classList.remove('rolling-value');rollTimers.delete(node);};rollTimers.set(node,setTimeout(cleanup,800));
 }
}
const surfaceRuns=new Map();
const scatterDirections=[[-1,-.55],[.9,-.65],[-.85,.7],[1,.55],[.2,.95],[-.35,-.9]];
function finishSurface(surface){
 const run=surfaceRuns.get(surface);if(!run)return;surfaceRuns.delete(surface);
 for(const animation of run.animations)animation?.cancel?.();for(const mark of run.marks)mark.remove();surface.classList.remove('motion-assembling');
}
function stopAllSurfaces(){for(const surface of [...surfaceRuns.keys()])finishSurface(surface);}
function assemblyTargets(surface){
 const width=window.innerWidth,height=window.innerHeight;
 const selector='.card,.company-hero,.company-metric,.inventory-tile,.metric,.record,.ops-record,.profile-heading,.profile-section,.profile-summary>div,.banner-item,.field,.admin-map,#map,.section-heading,h2,h3,.company-chart,.table-wrap,.ops-table-wrap,.support-conversation,.chat-head,.chat-message,.chat-compose';
 const candidates=[...surface.querySelectorAll(selector)].slice(0,180);const limit=width<600?20:36;
 return candidates.filter(node=>{if(node.closest('[hidden]')||node.closest('.tkt-skeleton'))return false;if(node.matches('h2,h3')&&node.closest('.section-heading'))return false;const rect=node.getBoundingClientRect();return rect.width>0&&rect.height>0&&rect.top<height+40&&rect.bottom>0;}).slice(0,limit);
}
function enterPage(surface){
 if(surface.hidden||surface.hasAttribute('data-initial-loading')||reduced.matches||!signed)return;
 finishSurface(surface);
 const targets=assemblyTargets(surface);if(!targets.length)return;
 const run={animations:[],marks:[]};surfaceRuns.set(surface,run);surface.classList.add('motion-assembling');
 const mobile=window.innerWidth<600,reach=mobile?76:210;
 for(const [index,node]of targets.entries()){
  const [dx,dy]=scatterDirections[index%scatterDirections.length],panel=node.matches('.card')&&targets.some(other=>other!==node&&node.contains(other));
  const distance=panel?reach*.18:reach;const x=Math.round(dx*distance),y=Math.round(dy*distance*.72),angle=panel?0:(index%2?-1:1)*(mobile?3.5:6);
  const duration=mobile?560:740,delay=Math.min(index*(mobile?18:22),mobile?150:220);
  const animation=play(node,[
   {opacity:0,transform:`translate3d(${x}px,${y}px,0) rotate(${angle}deg) scale(${panel ? .97 : .76})`,offset:0},
   {opacity:1,offset:.2},
   {opacity:1,transform:`translate3d(${-x*.018}px,${-y*.018}px,0) rotate(${-angle*.035}deg) scale(1.008)`,offset:.78},
   {opacity:1,transform:'translate3d(0,0,0) rotate(0deg) scale(1)',offset:1}
  ],{duration,delay,easing:'cubic-bezier(.16,1,.3,1)',fill:'backwards'});
  if(animation)run.animations.push(animation);
 }
 const root=surface.getBoundingClientRect();
 for(let index=0;index<Math.min(mobile?3:5,targets.length);index++){
  const node=targets[index],rect=node.getBoundingClientRect(),mark=document.createElement('i');mark.className='tkt-assembly-mark';mark.setAttribute('aria-hidden','true');mark.style.left=Math.max(4,rect.left-root.left+8)+'px';mark.style.top=Math.max(4,rect.top-root.top+8)+'px';surface.append(mark);run.marks.push(mark);
  const [dx,dy]=scatterDirections[index];const animation=play(mark,[{opacity:0,transform:`translate3d(${dx*reach}px,${dy*reach}px,0) scale(.4)`},{opacity:.75,offset:.25},{opacity:0,transform:'translate3d(0,0,0) scale(1)',offset:1}],{duration:mobile?480:650,delay:index*32,easing:'cubic-bezier(.16,1,.3,1)',fill:'both'});if(animation)run.animations.push(animation);
 }
 rollNumbers(surface);
 Promise.allSettled(run.animations.map(a=>a.finished||Promise.resolve())).then(()=>{if(surfaceRuns.get(surface)===run)finishSurface(surface);});
}
function cleanNumbers(surface){for(const [node,timer]of rollTimers){if(surface.contains(node)){clearTimeout(timer);node.querySelector('.number-roll')?.remove();node.classList.remove('rolling-value');rollTimers.delete(node);}}}
function sync(){for(const [source,item]of pairs){item.hidden=source.hidden;item.classList.toggle('selected',source.classList.contains('selected'));if(source.classList.contains('selected'))item.setAttribute('aria-current','page');else item.removeAttribute('aria-current');}const next=document.body.classList.contains('signed-in');const previous=signed,first=next&&!previous;signed=next;if(first)intro();if(!next&&previous){stopIntro();closeTools();stopAllSurfaces();}}
new MutationObserver(sync).observe(document.getElementById('navigation'),{subtree:true,attributes:true,attributeFilter:['hidden','class']});
new MutationObserver(sync).observe(document.body,{attributes:true,attributeFilter:['class']});
document.addEventListener('taktooka:page-leave',event=>{closeTools();stopAllSurfaces();const page=event.detail?.page;if(page)cleanNumbers(page);});
const registeredSurfaces=new WeakSet();
function watchSurface(surface){
 if(registeredSurfaces.has(surface))return;registeredSurfaces.add(surface);
 const isDialog=surface.tagName==='DIALOG';let visible=isDialog?surface.open:!surface.hidden;
 new MutationObserver(records=>{
  const next=isDialog?surface.open:!surface.hidden;
  if(!next){visible=false;finishSurface(surface);cleanNumbers(surface);return;}
  const opened=!visible;visible=true;
  const ready=records.some(r=>r.attributeName==='data-initial-loading'&&r.oldValue!==null&&!surface.hasAttribute('data-initial-loading'));
  if(opened||ready)enterPage(surface);
 }).observe(surface,{attributes:true,attributeOldValue:true,attributeFilter:['hidden','open','data-initial-loading']});
 if(visible&&signed)enterPage(surface);
}
for(const surface of document.querySelectorAll('.page,dialog.section-screen,#detailDialog,#chatScreen'))watchSurface(surface);
new MutationObserver(records=>{for(const record of records)for(const node of record.addedNodes){if(node.nodeType!==1)continue;if(node.matches('dialog.section-screen')){watchSurface(node);}for(const dialog of node.querySelectorAll('dialog.section-screen'))watchSurface(dialog);}}).observe(document.body,{childList:true});
document.addEventListener('focusin',event=>{for(const [surface]of surfaceRuns)if(surface.contains(event.target)){finishSurface(surface);break;}});
for(const type of ['wheel','touchstart'])document.addEventListener(type,event=>{for(const [surface]of surfaceRuns)if(surface.contains(event.target)){finishSurface(surface);break;}},{passive:true});
reduced.addEventListener?.('change',()=>{if(reduced.matches){stopIntro();stopAllSurfaces();for(const [node,timer]of rollTimers){clearTimeout(timer);node.querySelector('.number-roll')?.remove();node.classList.remove('rolling-value');}rollTimers.clear();}});
sync();
