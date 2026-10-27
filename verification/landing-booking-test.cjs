const fs=require('fs'),assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
(async()=>{
const html=fs.readFileSync(require('node:path').join(__dirname,'../dist/landing/index.html'),'utf8');
const dom=new JSDOM(html,{url:'https://x-spece.github.io/x-space-dashboard/landing/?page=page-test',runScripts:'outside-only'}),w=dom.window,calls=[];
w.fetch=async(url,init)=>{const name=url.split('/').pop(),body=JSON.parse(init.body);calls.push({name,body});return {ok:true,json:async()=>name==='x_public_landing'?{id:'page-test',product:{name:'منتج للاختبار',description:'وصف',stock:10,colors:['أحمر'],sizes:['M'],media:[]},sale:20000,freeDelivery:false,deliveryCost:5000}:'تم استلام الحجز'};};
w.eval(w.document.querySelector('script').textContent);await new Promise(r=>setImmediate(r));
const f=w.document.getElementById('booking');assert.equal(f.querySelector('button').disabled,false);assert.equal(w.document.querySelector('h1').textContent,'منتج للاختبار');
f.elements.name.value='زبون';f.elements.phone.value='٠٧٧٠٠٠٠٠٠١١';f.elements.address.value='الكرادة';f.elements.quantity.value='1';
f.dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));f.dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));await new Promise(r=>setImmediate(r));
const bookings=calls.filter(c=>c.name==='x_public_booking');assert.equal(bookings.length,1);assert.equal(bookings[0].body.p_page,'page-test');assert.equal(bookings[0].body.p_customer.phone,'07700000011');assert.equal(bookings[0].body.p_color,'أحمر');assert.equal(bookings[0].body.p_size,'M');assert.equal(w.document.getElementById('success').hidden,false);console.log('PASS customer page sends one validated server booking and shows success');w.close();
})().catch(e=>{console.error(e);process.exit(1)});
