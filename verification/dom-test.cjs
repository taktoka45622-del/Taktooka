const fs=require('fs'),vm=require('vm'),{JSDOM}=require('jsdom');
const dom=new JSDOM(fs.readFileSync('dist/index.html','utf8'),{url:'https://example.test',runScripts:'outside-only'}),w=dom.window;
w.HTMLDialogElement.prototype.showModal=function(){this.open=true};w.HTMLDialogElement.prototype.close=function(){this.open=false};
w.matchMedia=()=>({matches:true,addEventListener(){}});w.scrollTo=(x,y)=>{w.scrollY=y};
w.createClient=()=>({auth:{onAuthStateChange(){},getSession:async()=>({data:{session:null}})},rpc:async()=>({data:true})});
let s=fs.readFileSync('src/app.js','utf8').replace("import {createClient} from '@supabase/supabase-js';",'').replace(/start\(\);\s*$/,'');
vm.runInContext(s,dom.getInternalVMContext());
const run=s=>vm.runInContext(s,dom.getInternalVMContext());let count=0;
function test(ok,msg){if(!ok)throw new Error(msg);console.log('PASS '+msg);count++}
run('login()');test(w.document.querySelector('#login-form'),'login form rendered');run("preview=true;data={};render()");
for(const route of ['home','orders','products','categories','merchants','finance','support','exchange','notifications','settings','audit']){run(`route='${route}';render()`);test(w.document.querySelector('#page').innerHTML.length>40,'empty route '+route)}
run(`data={x_profiles:[{user_id:'merchant',phone:'07736578905',data:{name:'كرار',pageName:'أكس',province:'بغداد',area:'القاهرة'}}],x_orders:[{id:'test-order',merchant_id:'merchant',status:'معلق',created_at:'2026-10-01T00:00:00Z',payload:{customer:{name:'<img src=x onerror=alert(1)>',phone:'07736578905',province:'بغداد',address:'القاهرة'},sales:20000,delivery:5000,profit:10000,items:[{name:'منتج',quantity:1,sale:20000,unitCost:10000}]}}],x_withdrawals:[],x_products:[{id:'p',stock:5,active:true,sort_order:0,data:{name:'منتج',baseCost:10000,categories:[]}}]};preview=false;user={id:'owner'};allowed=true;route='orders';search='test-order';filter='';render();`);
test(w.document.querySelectorAll('.order-card').length===1,'search finds real order fixture');test(!w.document.querySelector('.order-card img'),'customer text escaped');
run("filter='تم التوصيل';page()");test(w.document.querySelectorAll('.order-card').length===0,'status filter excludes pending');
run("filter='';orderDetail('test-order')");test(w.document.querySelector('#new-status'),'order status control present');test(w.document.querySelector('#detail-screen')&&!w.document.querySelector('#dialog').open,'order details open as page');test(w.document.querySelector('#dialog-content').textContent.includes('منتج'),'historical line item shown');
run("closeProductPage();dialog.close();productForm('p')");test(w.document.querySelector('.product-full-page')&&!w.document.querySelector('#dialog').open,'product editor opens as a full page');test(w.document.querySelector('#f-stock').value==='5','product stock editor initialized');test(w.document.querySelector('#f-baseCost').value==='10000','wholesale editor initialized');
run("closeProductPage();dialog.close();merchantDetail('merchant')");test(w.document.querySelector('#dialog-content').textContent.includes('07736578905'),'merchant details render');
run("closeProductPage();dialog.close();route='finance';render()");test(w.document.querySelector('#page').textContent.includes('أرصدة التجار'),'merchant balances section present');
console.log(count+' DOM checks passed (mock data, no live writes)');

run("closeProductPage();route='home';render();");w.scrollY=320;run('setMenu(true)');test(w.document.body.classList.contains('menu-open'),'menu locks background');test(w.document.body.style.top==='-320px','menu preserves scroll offset');test(!w.document.querySelector('.sidebar').inert,'open menu accepts controls');w.document.querySelector('[data-action=menu-close]').click();test(!w.document.body.classList.contains('menu-open')&&w.scrollY===320,'backdrop closes and restores position');run('setMenu(true)');w.document.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape'}));test(!w.document.body.classList.contains('menu-open'),'escape closes navigation');run('setMenu(true)');w.document.querySelector('[data-route=orders]').click();test(!w.document.body.classList.contains('menu-open')&&w.document.querySelector('.sidebar').inert,'route navigation unlocks background and hides menu');

run("productForm('p')");test(w.document.querySelector('#f-minimumSale').required,'dashboard minimum sale is mandatory');test(w.document.querySelector('#f-imageFile').multiple,'gallery allows selecting multiple photos');test(w.document.querySelectorAll('#color-options input').length>=20,'expanded color palette');w.document.querySelector('#custom-color').value='لون خاص';w.document.querySelector('#add-color').click();test([...w.document.querySelectorAll('#color-options input')].some(i=>i.value==='لون خاص'&&i.checked),'custom color selected');w.document.querySelector('#f-baseCost').value='20000';w.document.querySelector('#f-appProfit').value='2000';w.document.querySelector('#f-discountEnabled').checked=true;w.document.querySelector('#discount-type').value='percent';w.document.querySelector('#discount-value').value='10';w.document.querySelector('#discount-value').dispatchEvent(new w.Event('input'));test(w.document.querySelector('#f-discountPrice').value==='19800','discount calculated on wholesale plus app profit');
run("productForm('p')");w.document.querySelector('#edit-description').click();test(!w.document.querySelector('#product-description-screen').hidden&&w.document.querySelector('#product-main-screen').hidden,'description opens independent screen');w.document.querySelector('#description-draft').value='وصف المنتج المحفوظ';w.document.querySelector('#save-description').click();test(w.document.querySelector('#f-description').value==='وصف المنتج المحفوظ'&&!w.document.querySelector('#product-main-screen').hidden,'save description returns and retains value');w.document.querySelector('#add-size').click();w.document.querySelector('#size-rows input').value='38';w.document.querySelector('#size-rows input').dispatchEvent(new w.Event('input'));w.document.querySelector('#add-size').click();const sizeInputs=w.document.querySelectorAll('#size-rows input');sizeInputs[1].value='40';sizeInputs[1].dispatchEvent(new w.Event('input'));test(w.document.querySelector('#f-sizes').value==='38، 40','multiple size fields synchronize saved list');w.document.querySelector('.remove-size').click();test(w.document.querySelector('#f-sizes').value==='40','size removal updates saved list');w.document.querySelector('#edit-description').click();w.document.querySelector('#description-draft').value='مسودة';w.document.querySelector('#description-back').click();test(w.document.querySelector('#f-description').value==='وصف المنتج المحفوظ','description back preserves saved text');test(w.document.querySelector('#f-sellingLimit').required,'maximum sale is explicitly required');
run(`closeProductPage();data.x_products=[{id:'old',created_at:'2026-01-01',sort_order:0,data:{name:'قديم',baseCost:1}},{id:'new',created_at:'2026-10-02',sort_order:99,data:{name:'جديد',baseCost:1}}];search='';route='products';render()`);
test(w.document.querySelector('.product h3').textContent==='جديد','new product appears above older product regardless of manual sort');
run(`data.x_tickets=[{id:'older-chat',merchant_id:'merchant',created_at:'2026-01-01',latest_at:'2026-10-02',type:'الأحدث',status:'open'},{id:'new-chat',merchant_id:'merchant',created_at:'2026-09-01',latest_at:'2026-09-01',type:'قديم',status:'open'}];route='support';filter='';render()`);
test(w.document.querySelector('.support-conversation').textContent.includes('الأحدث'),'new message moves existing conversation to top');

run(`data.x_products=[{id:'photos',stock:5,data:{name:'صور',baseCost:10,image:'https://example.test/main.jpg',media:[{asset:'https://example.test/main.jpg'},{asset:'https://example.test/second.jpg'}]}}];productForm('photos')`);
test(w.document.querySelectorAll('#photo-previews img').length===2,'published images appear without duplicates');
w.document.querySelector('#photo-previews button').click();
test(w.document.querySelector('#f-image').value==='https://example.test/second.jpg','removing main image promotes remaining image');
test(!w.document.querySelector('#f-gallery').value.includes('main.jpg'),'removed image excluded from saved gallery');
test(run("data.x_products[0].data.image")==='https://example.test/main.jpg','image changes stay local until save');
w.document.querySelector('#photo-previews button').click();
test(w.document.querySelector('#f-image').value===''&&w.document.querySelector('#f-gallery').value==='','removing all images clears saved fields');
run("closeProductPage();dialog.close();route='products';render()");
test(w.document.querySelector('[data-action=product-delete]'),'product delete button rendered');
run("action('product-delete','photos')");
test(w.document.querySelector('#dialog-content').textContent.includes('صور'),'deletion asks confirmation with product name');
run("closeProductPage();dialog.close();data.x_orders[0].status='قيد المراجعة';data.x_orders[0].payload.orderNumber=9;data.x_orders[0].payload.customer.phone2='07801234567';route='orders';search='000009';filter='';render()");
test(w.document.querySelectorAll('.order-card').length===1,'six digit order search finds order');
test(w.document.querySelector('.order-id').textContent.includes('000009'),'card shows six digit order number');
test(w.document.querySelector('.order-card .badge').textContent.includes('قيد المراجعة'),'review status shown');
test(w.document.querySelectorAll('.order-phone').length===2,'both customer phone numbers shown');
test(w.document.querySelector('[data-order-status]')&&!w.document.querySelector('[data-action=card-status]'),'status selector saves directly without button');
run("orderDetail('test-order')");
test(w.document.querySelector('.order-number').textContent==='# 000009','details show public number instead of internal ID');
test(w.document.querySelector('[data-action=order-chat]'),'order linked chat button rendered');
test(w.document.querySelector('.order-details').textContent.includes('ملاحظات للشركة'),'company notes section rendered');
test(!w.document.querySelector('[data-action=order-status]'),'details have no manual save status button');
run("data.x_orders[0].payload.items[0].image='https://example.test/product.jpg';data.x_orders[0].payload.items[0].note='ملاحظة منتج';orderDetail('test-order')");
test(w.document.querySelector('[data-action=order-image]')&&w.document.querySelector('[data-action=order-image-save]'),'product has enlarge and save buttons');
test(w.document.querySelector('.od-product').textContent.includes('ملاحظة منتج'),'product note rendered');
console.log(count+' total DOM checks passed');
(async()=>{
run("closeDetailPage();route='orders';search='';filter='';render();window.scrollY=210;orderDetail('test-order')");
test(w.document.querySelector('#detail-screen')&&!w.document.querySelector('dialog').open,'detail page is independent of dialog');
run("closeDetailPage()");test(!w.document.querySelector('#detail-screen')&&!w.document.querySelector('#app').hidden&&w.scrollY===210,'back restores original scroll and list');
run("orderFilterSheet()");test(w.document.querySelector('.order-filter-dialog'),'filter opens bottom sheet');
w.document.querySelector('[name=from]').value='2026-10-02';w.document.querySelector('#order-filter-form').dispatchEvent(new w.Event('submit',{cancelable:true}));
test(w.document.querySelectorAll('.order-card').length===0,'date range excludes earlier orders');
run("orderFilters={from:'',to:'',province:'',sort:'newest'};filter='';page();data.x_orders[0].status='قيد المراجعة';orderDetail('test-order');refresh=async()=>{};sb.rpc=async(name,args)=>{window.statusCall={name,args};return {data:true}};");
const select=w.document.querySelector('#new-status');select.value='قيد التجهيز';await run("updateOrderStatus('test-order',document.querySelector('#new-status'))");
test(w.statusCall.name==='x_admin_order_status'&&w.statusCall.args.p_status==='قيد التجهيز','select directly calls status API');
test(run("data.x_orders[0].status")==='قيد التجهيز','successful direct change updates status');
run("sb.rpc=async()=>({error:{message:'رفض تجريبي'}})");w.document.querySelector('#new-status').value='قيد التوصيل';await run("updateOrderStatus('test-order',document.querySelector('#new-status'))");test(w.document.querySelector('#new-status').value==='قيد التجهيز','failed change restores confirmed status');
run("closeDetailPage();data.x_tickets=[{id:'chat-test',merchant_id:'merchant',order_id:'test-order',type:'دعم طلب',status:'open'}];sb.from=()=>({select(){return this},eq(){return this},order(){return this},then(resolve){return Promise.resolve({data:[]}).then(resolve)}})");
await run("ticketDetail('chat-test')");test(w.document.querySelector('.chat-screen')&&!w.document.querySelector('dialog').open,'support chat opens as full page');test(w.document.querySelector('#detail-screen').textContent.includes('000009'),'chat header includes public order number');
await new Promise(r=>setTimeout(r,20));console.log(count+' total checks passed');w.close();
})().catch(e=>{console.error(e);process.exitCode=1});



run("closeDetailPage();route='orders';search='';filter='';render()");
w.document.querySelector('.reference-tabs').scrollLeft=-180;
w.document.querySelector('[data-filter="قيد المراجعة"]').click();
test(w.document.querySelector('.reference-tabs').scrollLeft===-180,'status filter preserves horizontal scroll');
test(w.document.querySelector('.order-card-secondary [data-action=order]'),'details occupy secondary card row');
test(!w.document.querySelector('.order-card [data-action=order-history]'),'history remains inside order details');
test(w.document.querySelector('.order-card').textContent.includes('مراسلة التاجر'),'card uses merchant chat label');
run("data.x_orders[0].status='تم التوصيل';filter='';page()");
test(w.document.querySelector('[data-action=order-edit]'),'edit control remains visible after delivery');
const statusHistory=run("historyChanges([{field:'status',before:'قيد التجهيز',after:'تم التوصيل'}])");
test(statusHistory.includes('حالة الطلب')&&statusHistory.includes('قبل:')&&statusHistory.includes('بعد:'),'history translates status change');
const orderHistory=run("historyChanges([{field:'order',before:{customer:{phone:'0771'},items:[{name:'منتج',sale:1000}]},after:{customer:{phone:'0772'},items:[{name:'منتج',sale:2000}]}}])");
test(orderHistory.includes('رقم الهاتف')&&orderHistory.includes('سعر البيع')&&!orderHistory.includes('customer'),'history expands customer and item changes');
const linked=run(`messageText('مرحبا https://example.com/a?q=1&x=2، www.example.org <img src=x> javascript:alert(1)')`);
const links=w.document.createElement('div');links.innerHTML=linked;
test(links.querySelectorAll('a').length===2,'HTTP and www links are clickable');
test(!links.querySelector('img'),'message HTML remains escaped');
test([...links.querySelectorAll('a')].every(a=>a.target==='_blank'&&a.rel.includes('noopener')),'message links open safely in new tab');
