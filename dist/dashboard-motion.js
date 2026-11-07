const icons={company:'◈',lines:'⇄',inventory:'▦',staff:'♙',exchanges:'⇆',overview:'◎',wheel:'◉',banners:'▧',pricing:'≋',rides:'➜',applications:'▣',users:'♧',coverage:'⌖',commerce:'％','restaurant-support':'♨',finance:'▤',rewards:'◇',support:'☏',favorites:'☆',security:'⊙',audit:'≡',server:'⌁'};
const rail=document.createElement('nav');
rail.className='dashboard-rail';rail.setAttribute('aria-label','أقسام تكتوكة');
const brand=document.createElement('button');brand.type='button';brand.className='rail-brand';brand.textContent='ت';brand.title='قائمة تكتوكة';brand.setAttribute('aria-label','فتح قائمة تكتوكة');brand.onclick=()=>document.getElementById('menuToggle').click();rail.append(brand);
const links=document.createElement('div');links.className='rail-links';rail.append(links);
const pairs=[];
for(const source of document.querySelectorAll('#navigation button[data-page]')){
 const item=document.createElement('button');item.type='button';item.textContent=icons[source.dataset.page]||'◈';item.title=source.textContent;item.setAttribute('aria-label',source.textContent);item.onclick=()=>source.click();links.append(item);pairs.push([source,item]);
}
document.body.append(rail);
const reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
let signed=false;
function sync(){
 for(const [source,item]of pairs){item.hidden=source.hidden;item.classList.toggle('selected',source.classList.contains('selected'));if(source.classList.contains('selected'))item.setAttribute('aria-current','page');else item.removeAttribute('aria-current');}
 const next=document.body.classList.contains('signed-in');
 if(next&&!signed&&!reduced.matches){document.querySelector('main').animate([{clipPath:'circle(0% at 50% 32%)',opacity:0},{clipPath:'circle(150% at 50% 32%)',opacity:1}],{duration:950,easing:'cubic-bezier(.22,1,.36,1)'});}
 signed=next;
}
new MutationObserver(sync).observe(document.getElementById('navigation'),{subtree:true,attributes:true,attributeFilter:['hidden','class']});
new MutationObserver(sync).observe(document.body,{attributes:true,attributeFilter:['class']});
for(const page of document.querySelectorAll('.page'))new MutationObserver(()=>{
 if(page.hidden||reduced.matches)return;
 const cards=[...page.children].filter(el=>el.matches('.card,.company-hero,.company-grid,.inventory-cards,.metrics'));
 cards.forEach((card,index)=>{card.getAnimations().forEach(a=>a.cancel());card.animate([{opacity:0,transform:'translateY(22px) scale(.975)',filter:'blur(5px)'},{opacity:1,transform:'translateY(0) scale(1)',filter:'blur(0)'}],{duration:620,delay:Math.min(index*65,325),easing:'cubic-bezier(.22,1,.36,1)',fill:'backwards'});});
}).observe(page,{attributes:true,attributeFilter:['hidden']});
sync();
