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
const themeKey='tkt-dashboard-theme',themeScheme=window.matchMedia('(prefers-color-scheme: dark)');
const themeButton=document.createElement('button');themeButton.type='button';themeButton.className='dashboard-theme-toggle';themeButton.id='dashboardThemeToggle';header.append(themeButton);
function storedTheme(){try{const value=localStorage.getItem(themeKey);return value==='dark'||value==='light'?value:null;}catch{return null;}}
function setDashboardTheme(theme,persist=false){
 document.documentElement.dataset.theme=theme;const dark=theme==='dark';themeButton.setAttribute('aria-label',dark?'تفعيل الوضع النهاري':'تفعيل الوضع الليلي');themeButton.setAttribute('aria-pressed',String(dark));themeButton.title=dark?'تفعيل الوضع النهاري':'تفعيل الوضع الليلي';
 themeButton.innerHTML=dark?'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/></svg><span>نهاري</span>':'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M21 13a9 9 0 0 1-10-10 9 9 0 1 0 10 10Z"/></svg><span>ليلي</span>';
 if(persist)try{localStorage.setItem(themeKey,theme);}catch{}
}
themeButton.onclick=()=>setDashboardTheme(document.documentElement.dataset.theme==='dark'?'light':'dark',true);
themeScheme.addEventListener?.('change',()=>{if(!storedTheme())setDashboardTheme(themeScheme.matches?'dark':'light');});
window.addEventListener('storage',event=>{if(event.key===themeKey)setDashboardTheme(storedTheme()||(themeScheme.matches?'dark':'light'));});
setDashboardTheme(storedTheme()||(themeScheme.matches?'dark':'light'));
const reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
let signed=false,introAnimation;
const rollTimers=new Map();
function play(node,frames,options){if(!node.animate)return null;const animation=node.animate(frames,options);return animation;}
function stopIntro(){introAnimation?.cancel?.();introAnimation=null;document.querySelector('.dashboard-intro')?.remove();document.body.classList.remove('dashboard-entering');}
function intro(){
 const page=document.querySelector('.page:not([hidden])');if(page)enterPage(page);
 if(reduced.matches)return;
 const overlay=document.createElement('div');overlay.className='dashboard-intro v22-intro';overlay.setAttribute('aria-hidden','true');
 overlay.innerHTML='<div class="intro-logo"><b>ت</b><strong>تكتوكة</strong></div>';document.body.append(overlay);
 introAnimation=play(overlay,[{clipPath:'circle(150% at 100% 100%)',opacity:1,offset:0},{clipPath:'circle(150% at 100% 100%)',opacity:1,offset:.2},{clipPath:'circle(0% at 100% 100%)',opacity:1,offset:1}],{duration:1100,easing:'cubic-bezier(.76,0,.24,1)',fill:'both'});
 if(introAnimation)introAnimation.finished?.then(()=>{if(overlay.isConnected)overlay.remove();introAnimation=null;}).catch(()=>{});else overlay.remove();
}
function rollNumbers(page){
 for(const node of [...(page.matches('.company-metric strong,.company-hero>strong,.metric>strong,.inventory-value')?[page]:[]),...page.querySelectorAll('.company-metric strong,.company-hero>strong,.metric>strong,.inventory-value')]){
  if(node.querySelector('.number-roll'))continue;const raw=node.textContent,match=raw.match(/^(\s*)([\d,]+(?:\.\d+)?)(.*)$/s);if(!match)continue;const end=Number(match[2].replaceAll(',',''));if(!Number.isFinite(end)||end<=0)continue;
  const reel=document.createElement('span');reel.className='number-roll';reel.setAttribute('aria-hidden','true');const precision=match[2].includes('.')?match[2].split('.')[1].length:0;
  for(let i=0;i<9;i++){const line=document.createElement('span');line.textContent=i===8?raw:match[1]+new Intl.NumberFormat('en-US',{maximumFractionDigits:precision}).format(Math.floor(end*i/8))+match[3];reel.append(line);}
  node.classList.add('rolling-value');node.append(reel);const cleanup=()=>{reel.remove();node.classList.remove('rolling-value');rollTimers.delete(node);};rollTimers.set(node,setTimeout(cleanup,800));
 }
}
const surfaceRuns=new Map();
function cleanNumbers(surface){for(const [node,timer]of rollTimers){if(surface.contains(node)){clearTimeout(timer);node.querySelector('.number-roll')?.remove();node.classList.remove('rolling-value');rollTimers.delete(node);}}}
function finishSurface(surface){
 const run=surfaceRuns.get(surface);if(!run)return;surfaceRuns.delete(surface);run.observer?.disconnect();
 for(const animation of run.animations)animation?.cancel?.();
 for(const node of run.nodes)node.removeAttribute('data-build-pending');
 surface.classList.remove('motion-assembling');cleanNumbers(surface);
}
function stopAllSurfaces(){for(const surface of [...surfaceRuns.keys()])finishSurface(surface);}
function assemblyTargets(surface){
 const body=surface.querySelector(':scope > .section-screen-body,:scope > #detailBody')||surface;
 return [...body.children].filter(node=>!node.hidden&&!node.matches('script,style,.tkt-skeleton')&&node.getBoundingClientRect().width).map(node=>({node}));
}
function enterPage(surface){
 if(surface.hidden||surface.hasAttribute('data-initial-loading')||reduced.matches||!signed||surfaceRuns.has(surface))return;
 const entries=assemblyTargets(surface);if(!entries.length)return;
 const run={nodes:entries.map(e=>e.node),animations:[],observer:null};surfaceRuns.set(surface,run);surface.classList.add('motion-assembling');
 const reveal=(node,index,late=false)=>{
  node.setAttribute('data-build-pending','');
  const animation=play(node,[{opacity:0,transform:'translate3d(0,18px,0) scale(.975)',filter:'blur(5px)',visibility:'visible'},{opacity:1,transform:'translate3d(0,0,0) scale(1)',filter:'blur(0px)',visibility:'visible'}],{duration:560,delay:late?0:Math.min(index,7)*48,easing:'cubic-bezier(.22,1,.36,1)',fill:'both'});
  if(!animation){node.removeAttribute('data-build-pending');return;}
  run.animations.push(animation);animation.finished?.then(()=>{if(surfaceRuns.get(surface)!==run)return;node.removeAttribute('data-build-pending');animation.cancel?.();rollNumbers(node);}).catch(()=>{});
 };
 entries.forEach(({node},index)=>reveal(node,index));
 run.observer=new MutationObserver(records=>{const added=[];for(const record of records)for(const node of record.addedNodes){if(node.nodeType!==1||node.hidden||node.matches('.number-roll,.tkt-skeleton')||node.closest('.number-roll,.leaflet-container,[data-build-pending]')||added.some(parent=>parent.contains(node)))continue;added.push(node);}for(const node of added){run.nodes.push(node);reveal(node,0,true);}});
 run.observer.observe(surface,{childList:true,subtree:true});
 const clock=play(surface,[{opacity:1},{opacity:1}],{duration:1050,fill:'both'});if(clock){run.animations.push(clock);clock.finished?.then(()=>{if(surfaceRuns.get(surface)===run)finishSurface(surface);}).catch(()=>{});}else finishSurface(surface);
}
function sync(){for(const [source,item]of pairs){item.hidden=source.hidden;item.classList.toggle('selected',source.classList.contains('selected'));if(source.classList.contains('selected'))item.setAttribute('aria-current','page');else item.removeAttribute('aria-current');}const next=document.body.classList.contains('signed-in');const previous=signed,first=next&&!previous;signed=next;if(first)intro();if(!next&&previous){stopIntro();closeTools();stopAllSurfaces();}}
new MutationObserver(sync).observe(document.getElementById('navigation'),{subtree:true,attributes:true,attributeFilter:['hidden','class']});new MutationObserver(sync).observe(document.body,{attributes:true,attributeFilter:['class']});
document.addEventListener('taktooka:page-leave',event=>{closeTools();stopAllSurfaces();});
document.addEventListener('taktooka:surface-enter',event=>{if(event.detail?.surface)enterPage(event.detail.surface);});
const registeredSurfaces=new WeakSet();
function watchSurface(surface){
 if(registeredSurfaces.has(surface))return;registeredSurfaces.add(surface);const isDialog=surface.tagName==='DIALOG';let visible=isDialog?surface.open:!surface.hidden;
 new MutationObserver(records=>{const next=isDialog?surface.open:!surface.hidden;if(!next){visible=false;finishSurface(surface);return;}const opened=!visible;visible=true;if(surface.hasAttribute('data-initial-loading')){finishSurface(surface);return;}const ready=records.some(r=>r.attributeName==='data-initial-loading'&&r.oldValue!==null);if(opened||ready)enterPage(surface);}).observe(surface,{attributes:true,attributeOldValue:true,attributeFilter:['hidden','open','data-initial-loading']});
 if(visible&&signed)enterPage(surface);
}
for(const surface of document.querySelectorAll('.page,dialog.section-screen,#detailDialog,#chatScreen'))watchSurface(surface);
new MutationObserver(records=>{for(const record of records)for(const node of record.addedNodes){if(node.nodeType!==1)continue;if(node.matches('dialog.section-screen'))watchSurface(node);for(const dialog of node.querySelectorAll('dialog.section-screen'))watchSurface(dialog);}}).observe(document.body,{childList:true});
reduced.addEventListener?.('change',()=>{if(reduced.matches){stopIntro();stopAllSurfaces();}});
sync();document.documentElement.classList.remove('tkt-build-startup');
