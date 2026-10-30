import {createCommercePage} from './commerce.js?v=1.7.0';
import {createServerMonitor} from './server-monitor.js?v=1';
import {createAccountAdmin} from './account-admin.js?v=1.6.93';
import {setupPhoneActions,normalizeWhatsAppPhone,whatsappUrl} from './phone-actions.js?v=1.6.91';
import {createGlobalSearch} from './global-search.js?v=1';
import {createOperations} from './operations.js?v=1.6.90';
import {playNoticeSound} from './notification-sound.js?v=1';
import {setupKeyboardShortcuts} from './keyboard-shortcuts.js?v=1';
import {createAppNavigation,requestAppBack,navigationChanged,navigationWillChange} from './app-navigation.js?v=4';
import {openSectionScreen,closeSectionScreen,closeAllSectionScreens,getSectionScreens} from './screen-navigation.js?v=3';
import {normalizeIraqiPhone} from './agents/phone.js?v=4';
import {createExchangesPage} from './exchanges.js?v=1.6.93';
import {createCouponCardPrinter} from './coupon-card-printer.js?v=1.6.68';
import {createCouponRewards} from './coupon-rewards.js?v=1.6.89';
import {createCompanyPage} from './company-performance.js?v=1.6.61';
import {createRenderCache, createRequestTracker, debounceTask} from './performance.js?v=1.6.42';
const renderCache=createRenderCache(), requestTracker=createRequestTracker();
let appNavigation=null,detailAction=null;let navigationEpoch=0;const pageScroll=new Map();
import { englishDigits, displayClock, displayTime, displayDateTime, setupEnglishNumbers, setupTwelveHourInputs, setupGroupedNumbers } from './display-format.js?v=1.6.41';
import { createEmergencyAlarm } from './emergency-alarm.js?v=1.6.21';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.95.3';
const db=createClient('https://typbkzwbrmkrfkfxjrgi.supabase.co','sb_publishable_Oto-5IRPHgWceHq_uzrsiw_JBBZbAOT',{auth:{storageKey:'taktooka-web-admin'}});
const $=id=>document.getElementById(id);const status=text=>$('status').textContent=text;
const governorates=['بغداد','البصرة','نينوى','أربيل','السليمانية','دهوك','حلبجة','كركوك','ديالى','الأنبار','صلاح الدين','بابل','كربلاء','النجف','واسط','القادسية','ذي قار','ميسان','المثنى'];
for(const name of governorates){const option=document.createElement('option');option.textContent=name;$('governorate').append(option)}
let zones=[],settings={},map,overlay,points=[],drawing=false,editing=null,busy=false;
function message(error){if(String(error?.message).includes('ANNOUNCEMENT_SENT'))return 'سبق إرسال إشعار توفر التطبيق';if(String(error?.message).includes('APP_NOT_AVAILABLE'))return 'احفظ رابط التحميل وفعّل توفر التطبيق أولًا';if(String(error?.message).includes('INVALID_URL'))return 'اكتب رابط تحميل صحيح يبدأ https://';if(String(error?.message).includes('ADMIN_REQUIRED'))return 'هذا الحساب ليس حساب إدارة';if(String(error?.message).includes('SEARCH_IN_PROGRESS'))return 'توجد طلبات قيد البحث؛ انتظر انتهاءها ثم احفظ';if(String(error?.message).includes('PERMISSION_DENIED'))return 'ما عندك صلاحية لهذا الإجراء';if(String(error?.message).includes('OWNER_REQUIRED'))return 'إدارة الموظفين متاحة للمالك فقط';if(String(error?.message).includes('coupon_printed_single_use'))return 'الكارت المطبوع ثابت: رحلة مجانية واحدة واستخدام واحد';if(String(error?.message).includes('INVALID_CARD_BATCH'))return 'حدد من 1 إلى 100,000 كارت وصلاحية بالمستقبل';if(String(error?.message).includes('COUPON_TYPE_LOCKED'))return 'نوع الكود ثابت بعد تفعيله من زبون؛ أنشئ كودًا جديدًا';if(String(error?.message).includes('COUPON_USE_LIMIT'))return 'عدد الاستخدامات أقل من الاستخدامات المسجلة';if(String(error?.message).includes('INVALID_EXPIRY'))return 'حدد تاريخ صلاحية بالمستقبل';if(String(error?.message).includes('coupons_amount_check'))return 'مبلغ الخصم من 250 إلى 100,000 دينار';if(String(error?.message).includes('PHONE_EXISTS'))return 'رقم الهاتف مستخدم بحساب آخر';return error?.message||'تعذر تنفيذ العملية، حاول مرة ثانية'}
async function rpc(action,data={}){const {data:result,error}=await db.rpc('tkt_dispatch',{p_action:action,p_data:data});if(error)throw error;return result}
function render(){ $('zones').replaceChildren();overlay.clearLayers();for(const zone of zones){const row=document.createElement('div');row.className='zone';const name=document.createElement('strong');name.textContent=zone.name;const controls=document.createElement('div');const edit=document.createElement('button');edit.textContent='تعديل الحدود';edit.onclick=()=>{editing=zone.id;$('name').value=zone.name;points=zone.geometry.coordinates[0].slice(0,-1).map(([lng,lat])=>[lat,lng]);drawing=true;preview();map.fitBounds(points);status('تعديل المنطقة: اضغط على الخريطة لإضافة نقاط، ثم اعتماد المنطقة')};const remove=document.createElement('button');remove.className='secondary';remove.textContent='حذف';remove.onclick=()=>{if(confirm('إزالة هذه المنطقة من التغطية؟')){zones=zones.filter(z=>z.id!==zone.id);render();status('التغيير لم يُحفظ بعد')}};controls.append(edit,remove);row.append(name,controls);$('zones').append(row);L.polygon(zone.geometry.coordinates[0].map(([lng,lat])=>[lat,lng]),{color:'#d91e27',weight:2}).addTo(overlay)}}
let draft;function preview(){if(draft)map.removeLayer(draft);draft=L.polygon(points,{color:'#e5a600',dashArray:'5 5'}).addTo(map);$('hint').textContent=`عدد نقاط الحدود: ${points.length}`}
function initMap(){if(map)return;map=mapFor('map');overlay=L.layerGroup().addTo(map);map.on('click',e=>{if(drawing){points.push([e.latlng.lat,e.latlng.lng]);preview()}})}
async function load(){await refreshDashboardAccess();$('login').hidden=true;$('admin').hidden=false;$('globalSearchButton').hidden=false;document.body.classList.add('signed-in');$('logout').hidden=false;const requestedPage=new URL(location.href).searchParams.get('page');const first=requestedPage==='exchanges'&&canView('exchanges')?'exchanges':canView('inventory')?'inventory':permissionPages.find(([key])=>canView(key))?.[0];if(!first)throw new Error('لا توجد أقسام مسموحة لهذا الحساب');showPage(first);await loadPage(first);applyDashboardPermissions();startLive();startInventoryRefresh();await startNotifications();await startDashboardNavigation();status('مرحبًا '+(dashboardAccess.name||'')+' · تم تحميل لوحة إدارة تكتوكة')}
async function run(action){if(busy){status('جاري تنفيذ العملية الحالية، انتظر لحظة ثم أعد المحاولة');return;}const navigation=appNavigation;navigation?.begin();busy=true;document.getElementById('admin').setAttribute('aria-busy','true');try{await action();liveDirtyPages.delete(activePage);scheduleLiveRefresh()}catch(e){status(message(e))}finally{busy=false;document.getElementById('admin').removeAttribute('aria-busy');navigation?.end();}}
$('loginForm').onsubmit=e=>{e.preventDefault();run(async()=>{const ph=normalizeIraqiPhone($('phone').value);if(!ph)throw new Error('رقم هاتف الإدارة غير صحيح. اكتب الرقم المسجّل بالداشبورد.');const {data,error}=await db.functions.invoke('taktooka-admin-login',{body:{phone:ph,pin:$('pin').value}});$('pin').value='';if(error||!data?.refresh_token){let code=data?.error;try{if(!code&&error?.context)code=(await error.context.json()).error;}catch{}const messages={INVALID_ADMIN_LOGIN:'رقم الإدارة أو كلمة السر غير صحيحة.',ADMIN_LOGIN_LOCKED:'محاولات دخول الإدارة متوقفة مؤقتًا؛ انتظر 15 دقيقة ثم حاول.',ADMIN_LOGIN_UNAVAILABLE:'خدمة دخول الإدارة غير متاحة حاليًا؛ حاول بعد قليل.'};throw new Error(messages[code]||'تعذّر الاتصال بخدمة الدخول؛ تحقق من الاتصال وحاول مرة ثانية.');}const session=await db.auth.refreshSession({refresh_token:data.refresh_token});if(session.error)throw session.error;await load()})};
$('draw').onclick=()=>{drawing=true;editing=null;points=[];preview();status('انقر حول المنطقة لرسم حدود مغلقة، ثم اعتماد المنطقة')};$('undo').onclick=()=>{points.pop();preview()};
$('finish').onclick=()=>{if(points.length<3)return status('حدد ثلاث نقاط على الأقل');const name=$('name').value.trim();if(!name)return status('اكتب اسم المنطقة');if(points.some(([lat,lng])=>lat<29||lat>38||lng<38||lng>49))return status('المنطقة يجب أن تكون داخل العراق');const ring=points.map(([lat,lng])=>[lng,lat]);ring.push([...ring[0]]);const zone={id:editing||`zone_${crypto.randomUUID().slice(0,8)}`,name:editing?name:`${$('governorate').value} — ${name}`,geometry:{type:'Polygon',coordinates:[ring]}};zones=zones.filter(z=>z.id!==zone.id);zones.push(zone);drawing=false;points=[];if(draft)map.removeLayer(draft);render();status('تم اعتماد المنطقة محليًا؛ اضغط حفظ التغييرات لتفعيلها بالتطبيق')};
$('save').onclick=()=>run(async()=>{if(!zones.length)throw new Error('أضف منطقة خدمة واحدة على الأقل');if(drawing)throw new Error('اعتمد حدود المنطقة قبل الحفظ');await manage('dispatch_configure',{zones,search_s:Number($('search').value),max_eta_s:Number($('eta').value)*60,stale_s:Number($('stale').value)});await load();showPage('coverage');status('تم حفظ وتفعيل مناطق الخدمة بالتطبيق: '+zones.map(z=>z.name).join('، '))});$('reload').onclick=()=>run(load);$('logout').onclick=()=>run(async()=>{appNavigation?.clear();appNavigation=null;closeAllSectionScreens();stopLive();clearInterval(inventoryTimer);companyPage.reset();exchangesPage.reset();dashboardAccess=null;await stopNotifications(true);closeDetail();await db.auth.signOut();$('admin').hidden=true;$('globalSearchButton').hidden=true;document.body.classList.remove('signed-in');setMenu(false);$('login').hidden=false;$('logout').hidden=true;zones=[];rides=[];users=[];$('rideList').replaceChildren();$('userList').replaceChildren();status('تم تسجيل الخروج')});


let pricing,tiers=[],rides=[],users=[];
const priceKeys=['night_amount','night_min_m','night_start','night_end','overflow_step_m','overflow_amount','max_fare'];
function localPhone(v){const d=String(v??'').replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-0x660)).replace(/[^0-9]/g,'');return /^9647[0-9]{9}$/.test(d)?'0'+d.slice(3):/^7[0-9]{9}$/.test(d)?'0'+d:d;}
const money=n=>new Intl.NumberFormat('en-US').format(n)+' د.ع';
const stateNames={pending:'قيد البحث',accepted:'الكابتن بالطريق',arrived:'وصل الكابتن',in_progress:'الرحلة جارية',completed:'مكتملة',cancelled:'ملغية'};

function tripKind(r){return r.round_trip===true?'ذهاب وإياب':'ذهاب فقط';}
function tripStage(r){
 if(!r.round_trip)return stateNames[r.status]||r.status||'—';
 if(r.status==='completed')return 'اكتمل الذهاب والإياب';
 if(r.status==='cancelled')return 'ملغية';
 if(r.status!=='in_progress')return 'بانتظار بدء الذهاب';
 return {outbound:'الذهاب',waiting:'انتظار الزبون للرجعة',returning:'الرجعة إلى نقطة الانطلاق'}[r.round_trip_stage]||'الذهاب';
}
function tripFacts(r,detail=false){
 const rows=[['نوع المشوار',tripKind(r)]];if(r.coupon_code)rows.push(['كود الخصم / الجائزة',r.coupon_code],['نوع الكود',r.coupon_reward_type==='free_ride'?'رحلة مجانية · يوم اشتراك للكابتن بعد الإكمال':'خصم بمبلغ']);
 if(!r.round_trip)return rows;
 const minutes=Number(r.wait_minutes)||0,fee=Number(r.waiting_fee)||0;
 rows.push(['مرحلة المشوار',tripStage(r)],['وقت الانتظار المحدد',minutes+' دقيقة'],['أجرة الانتظار',money(fee)]);
 if(detail){
  const roadTotal=Number(r.fare)-fee;
  rows.push(['كروة الذهاب',money(roadTotal/2)],['كروة الإياب',money(roadTotal/2)],
    ['الكروة مع الانتظار',money(r.fare)],['الرجعة إلى',r.pickup_name||'نقطة الانطلاق الأصلية'],
    ['مسافة الذهاب',((r.route_distance_m||0)/1000).toFixed(2)+' كم'],
    ['مسافة الإياب',((r.return_distance_m||0)/1000).toFixed(2)+' كم'],
    ['بدء الانتظار',dates(r.wait_started_at)]);
 }
 if(r.status==='in_progress'&&r.round_trip_stage==='waiting'&&r.wait_started_at){
  const start=Date.parse(r.wait_started_at),clock=Number.isFinite(serverTime)?serverTime:Date.now();
  if(Number.isFinite(start)){
   const remaining=Math.max(0,Math.min(minutes*60,Math.ceil((start+minutes*60000-clock)/1000)));
   rows.push(['الانتظار المتبقي',remaining?String(Math.floor(remaining/60)).padStart(2,'0')+':'+String(remaining%60).padStart(2,'0'):'انتهى وقت الانتظار المحدد']);
  }
 }
 return rows;
}
function tripMapData(r){
 const returning=r.round_trip===true&&r.round_trip_stage==='returning';
 const lines=[];
 if(r.geometry)lines.push({geometry:r.geometry,color:'#d92527',label:returning?'مسار الرجعة الحالي':'مسار الذهاب الحالي'});
 if(r.round_trip&&r.return_geometry&&!returning)lines.push({geometry:r.return_geometry,color:'#2878c8',dashArray:'8 6',label:'مسار الرجعة'});
 return {lines,points:[[r.pickup,returning?'الوصول · الرجعة':'الانطلاق'],[r.destination,returning?'الانطلاق · الرجعة':'الوصول']]};
}

async function pricingRpc(action,data={}){const {data:result,error}=await db.rpc('tkt_pricing',{p_action:action,p_data:data});if(error){if(error.message.includes('PRICING_CONFLICT'))throw new Error('التسعيرة تغيّرت من جلسة ثانية؛ أعد تحميلها قبل الحفظ');throw error}return result}
function tierNumber(value){const normalized=String(value).replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-0x660)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-0x6f0)).replace(/[,٬\s]/g,'');return normalized===''?null:Number(normalized);}
function tierProblem(){
 if(!tiers.length||tiers.length>30)return 'أضف من شريحة واحدة إلى 30 شريحة';
 let previous=0;
 for(let i=0;i<tiers.length;i++){const t=tiers[i],from=t.from_m??(i?tiers[i-1].up_to_m:0);
  if(!Number.isInteger(from)||from!==previous)return i===0?'الشريحة الأولى تبدأ من صفر متر':'بداية الشريحة يجب أن تساوي نهاية الشريحة السابقة';
  if(!Number.isInteger(t.up_to_m)||t.up_to_m<=from||t.up_to_m>100000)return 'أدخل نهاية أكبر من البداية لكل شريحة، وبحد أقصى 100,000 متر';
  if(!Number.isInteger(t.fare)||t.fare<0||t.fare>1000000)return 'أدخل سعرًا صحيحًا لكل شريحة من صفر إلى 1,000,000 دينار';
  previous=t.up_to_m;
 }
 return null;
}
function priceNotice(){const issue=tierProblem(),descending=tiers.some((t,i)=>i&&Number.isFinite(t.fare)&&Number.isFinite(tiers[i-1].fare)&&t.fare<tiers[i-1].fare);$('priceWarning').hidden=!issue&&!descending;$('priceWarning').textContent=issue||'انتبه: كروة إحدى الشرائح أقل من الشريحة السابقة. راجع الأسعار قبل الحفظ.';}
function renderTiers(){
 const body=$('tiers');body.replaceChildren();
 tiers.forEach((tier,i)=>{
  if(!Object.hasOwn(tier,'from_m'))tier.from_m=i?tiers[i-1].up_to_m:0;
  const tr=document.createElement('tr');
  for(const [key,label]of [['from_m','بداية المسافة بالمتر'],['up_to_m','نهاية المسافة بالمتر'],['fare','الكروة بالدينار']]){
   const td=document.createElement('td'),input=document.createElement('input');input.type='text';input.inputMode='numeric';input.dir='ltr';input.value=tier[key]??'';input.placeholder=key==='fare'?'السعر بالدينار':'المسافة بالمتر';input.dataset.tierField=key;input.setAttribute('aria-label',label+' · الشريحة '+(i+1));input.disabled=!canEdit('pricing');
   input.oninput=()=>{
    tier[key]=tierNumber(input.value);
    if(key==='from_m'&&i>0){tiers[i-1].up_to_m=tier[key];body.children[i-1].querySelector('[data-tier-field="up_to_m"]').value=tier[key]??'';}
    if(key==='up_to_m'&&i<tiers.length-1){tiers[i+1].from_m=tier[key];body.children[i+1].querySelector('[data-tier-field="from_m"]').value=tier[key]??'';}
    priceNotice();
   };td.append(input);tr.append(td);
  }
  const td=document.createElement('td'),remove=document.createElement('button');remove.type='button';remove.className='secondary';remove.textContent='حذف';remove.disabled=!canEdit('pricing');remove.onclick=()=>{tiers.splice(i,1);tiers.forEach((t,j)=>t.from_m=j?tiers[j-1].up_to_m:0);renderTiers();};td.append(remove);tr.append(td);body.append(tr);
 });priceNotice();
}
function addPricingTier(){if(!canEdit('pricing'))return status('صلاحيتك للعرض فقط');if(tiers.length>=30)return status('الحد الأقصى 30 شريحة');if(tiers.length&&tierProblem())return status('أكمل بيانات الشرائح الحالية قبل إضافة شريحة جديدة');tiers.push({from_m:tiers.at(-1)?.up_to_m??0,up_to_m:null,fare:null});renderTiers();$('tiers').lastElementChild.querySelector('[data-tier-field="up_to_m"]').focus();}

async function loadPricing(){const previousRevision=pricing?.revision;pricing=await pricingRpc('get');tiers=structuredClone(pricing.tiers);for(const key of priceKeys)$(key).value=pricing[key];$('priceMeta').textContent=`إصدار التسعيرة ${pricing.revision} · آخر تعديل ${dates(pricing.updated_at)}`;renderTiers();if(previousRevision!==pricing.revision)$('previewResult').textContent=''}
function pricingInput(){const issue=tierProblem();if(issue)throw new Error(issue);const data={tiers:tiers.map(({up_to_m,fare})=>({up_to_m,fare})),expected_revision:pricing.revision};for(const k of priceKeys){data[k]=tierNumber($(k).value);if(!Number.isInteger(data[k])||data[k]<0)throw new Error('أدخل أرقامًا صحيحة في إعدادات التسعيرة')}if(data.night_start>23||data.night_end>23||data.overflow_step_m<1)throw new Error('تحقق من ساعات الليل والمسافة الإضافية');return data}
$('addTier').onclick=addPricingTier;
$('savePricing').onclick=()=>run(async()=>{const data=pricingInput();await manage('pricing_save',data);await loadPricing();status('تم حفظ التسعيرة وتفعيلها للمشاوير الجديدة')});
$('reloadPricing').onclick=()=>run(loadPricing);
$('previewFare').onclick=()=>run(async()=>{const distance=Number($('previewDistance').value);if(!Number.isFinite(distance)||distance<=0)throw new Error('أدخل مسافة موجبة');const day=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Baghdad'});const at=`${day}T${$('previewTime').value==='night'?'23':'12'}:00:00+03:00`;const result=await pricingRpc('preview',{distance_m:distance,at});$('previewResult').textContent=`${money(result.fare)} — أساس ${money(result.base_fare)} + ليل ${money(result.night_surcharge)}`});
let activePage='overview';
function showPage(name,record=true){if(record)navigationWillChange();closeAllSectionScreens();if($('detailDialog').open||!$('chatScreen').hidden)closeDetail();if(!canView(name))throw new Error('PERMISSION_DENIED');if(name!==activePage){if(activePage==='company')companyPage.cancel();pageScroll.set(activePage,window.scrollY);requestTracker.clear();requestAnimationFrame(()=>window.scrollTo({top:pageScroll.get(name)||0,behavior:'instant'}));}setMenu(false,false);activePage=name;const selected=document.querySelector(`[data-page="${name}"]`);if(selected)$('pageTitle').textContent=selected.textContent;document.querySelectorAll('.page').forEach(el=>el.hidden=el.id!=='page-'+name);document.querySelectorAll('[data-page]').forEach(el=>el.classList.toggle('selected',el.dataset.page===name));if(name==='coverage'&&map)setTimeout(()=>map.invalidateSize(),0);if(record)queueMicrotask(()=>navigationChanged());}
function text(tag,value){const el=document.createElement(tag);el.textContent=englishDigits(value);return el}


async function manage(action,data={}){
 const reason=$('operationReason')?.value.trim();const {data:result,error}=await db.rpc(reason?'tkt_operations':'tkt_manage',reason?{p_action:'manage',p_data:{action,data,reason}}:{p_action:action,p_data:data});
 if(error)throw error;return result;
}
const actionNames={user_edit:'تعديل الحساب',role:'تغيير نوع الحساب',renew:'تجديد الاشتراك',block:'تغيير الحظر',subscription_edit:'تعديل نهاية الاشتراك',topup:'شحن محفظة',settle:'تسديد مستحقات',coupon_admin:'حفظ كود خصم',coupon_delete:'حذف كود خصم',favorite_edit:'تعديل عنوان',favorite_delete:'حذف عنوان',ride_cancel:'إلغاء رحلة',recovery_send:'رد استرجاع الحساب',send:'رد الدعم',unlock_phone:'فتح محاولات الدخول',password_reset_record:'تعيين كلمة سر',archive:'أرشفة',restore:'استرجاع',pricing_save:'تعديل التسعيرة',dispatch_configure:'تعديل التغطية والتوزيع',application_reject:'رفض طلب كابتن',captain_approved:'الموافقة على تسجيل المركبة',captain_changes_required:'إعادة تسجيل المركبة للتعديل'};
const archiveNames={user:'حساب',ride:'رحلة',support:'دردشة دعم',recovery:'استرجاع حساب'};
const ledgerNames={topup:'شحن',settle:'تسديد مستحقات',ride_payment:'دفع مشوار',refund:'استرجاع مبلغ',captain_earning:'أرباح كابتن'};
const dates=displayDateTime;
const activeStates=['pending','accepted','arrived','in_progress'];
let liveMap,liveLayers,liveChannel,liveTimer,liveEventTimer,lastLiveRefresh=0,refreshing=false,serverTime=Date.now(),captains=[];const liveCaptainMarkers=new Map();
let rideMovingMarker=null;
let dialogMap,dialogLayer,dialogMode=null,dialogKey=null,dialogEpoch=0,dialogRefreshing=false,chatSignature=null,finance={},favorites=[],security=[],audit=[],archives=[],recovery=[],openLedger=null;
let profileLiveChannel,profileMarker,profileMotionFrame,profileStatusTimer,profileLiveData,profileServerOffset=0,profileFollow=true,profileCentered=false,profilePositionTime=-Infinity;
function button(label,fn,cls='secondary'){const el=text('button',label);el.type='button';el.className=cls;const mutation=/^(تعديل|حفظ|تأكيد|تعيين|تجديد|حظر|رفع الحظر|فتح المحاولات|إيقاف|تفعيل|أرشفة|استرجاع|إلغاء الرحلة|حذف|شحن|تسديد|موافقة|رفض|تفعيل كابتن|إلغاء صلاحية|إرسال)/.test(label);const page=label==='تعيين كلمة سر'?'security':activePage;if(mutation&&!canEdit(page)){el.disabled=true;el.title='صلاحيتك في هذا القسم للعرض فقط';}el.onclick=()=>run(fn);return el}
function facts(entries){const dl=text('dl','');dl.className='facts';for(const [label,value]of entries){const item=text('div','');item.append(text('dt',label),text('dd',value??'—'));dl.append(item)}return dl}
function record(title,subtitle,controls=[]){const row=text('article','');row.className='record';const info=text('div','');info.append(text('strong',title),Array.isArray(subtitle)?facts(subtitle):text('p',subtitle));const actions=text('div','');actions.className='controls';actions.append(...controls);row.append(info,actions);return row}
function empty(list){if(!list.childElementCount)list.append(Object.assign(text('p','ماكو بيانات حالياً'),{className:'empty'}))}
function inputField(label,value,type='text'){const box=text('label',label),input=document.createElement('input');box.className='field';input.type=type;input.value=value??'';box.append(input);return {box,input}}
function openDetail(title,route=null){appNavigation?.save();closeDetail();detailAction=route;if(route)queueMicrotask(()=>appNavigation?.commit());$('detailTitle').textContent=title;$('detailBody').replaceChildren();if(/^(تعديل|شحن|تسجيل تسديد|تغيير)/.test(title)){const reason=text('label','سبب العملية — اختياري'),input=document.createElement('input');input.id='operationReason';input.maxLength=500;reason.append(input);$('detailBody').append(reason);}document.body.classList.add('detail-open');$('detailDialog').showModal();$('detailDialog').scrollTop=0;return $('detailBody')}
function closeDetail(){detailAction=null;document.body.classList.remove('detail-open');stopCaptainProfile();if(!$('chatScreen').hidden){$('chatScreen').hidden=true;document.body.classList.remove('chat-open');$('chatWorkspace').replaceChildren();}dialogEpoch++;dialogMode=null;dialogKey=null;chatSignature=null;if(dialogMap){dialogMap.remove();dialogMap=null;dialogLayer=null}if($('detailDialog').open)$('detailDialog').close()}
$('closeDialog').onclick=()=>requestAppBack(closeDetail);$('detailDialog').addEventListener('cancel',event=>{event.preventDefault();requestAppBack(closeDetail);});$('detailDialog').addEventListener('close',()=>{if(!$('detailDialog').open)document.body.classList.remove('detail-open');});
function mapFor(id){const m=L.map(id,{maxZoom:19}).setView([33.54844,44.41179],14);L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxNativeZoom:19,maxZoom:19,keepBuffer:2,updateWhenIdle:true,attribution:'© OpenStreetMap contributors'}).addTo(m);requestAnimationFrame(()=>{if(document.getElementById(id)&&m.getContainer()?.isConnected)m.invalidateSize({pan:false});});return m}
function fresh(p){return !!p.location_at && Math.max(0,serverTime-Date.parse(p.location_at))<=15000}
function locationLabel(p){const age=p.location_at?Math.max(0,Math.floor((serverTime-Date.parse(p.location_at))/1000)):null;return age===null?'لم يصل موقع':age<=15?'مباشر · قبل '+age+' ثانية':'متأخر · قبل '+age+' ثانية'}
function captainMarker(p){return L.marker([p.lat,p.lng],{icon:L.divIcon({className:'',html:`<div class="map-marker ${fresh(p)?'':'muted-marker'}"></div>`,iconSize:[20,20]})}).bindPopup(text('span',`${p.name||'كابتن'} · ${locationLabel(p)} · ${dates(p.location_at)}`))}
async function loadOverview(){
 const [stats,snapshot]=await Promise.all([manage('overview'),liveSnapshot()]);serverTime=Date.parse(stats.server_now);stats.applications=snapshot.pending_applications??stats.applications;stats.online=snapshot.captains.filter(fresh).length;
 $('metrics').replaceChildren();for(const [label,key]of [['مستخدم','users'],['كابتن','captains'],['كابتن موقعه مباشر','online'],['رحلة فعالة','active_rides'],['رحلة اليوم','today_rides'],['قيمة الرحلات المكتملة اليوم','today_completed'],['طلب كابتن','applications']]){const box=text('div',label);box.className='metric';box.prepend(text('strong',key==='today_completed'?money(stats[key]):String(stats[key])));$('metrics').append(box)}
 $('workerStatus').textContent=`آخر تحديث توزيع: ${dates(stats.worker?.heartbeat)}${stats.worker?.last_error?' · تنبيه في توزيع الطلبات':''}`;
 captains=snapshot.captains;
 if(!liveMap){liveMap=mapFor('liveMap');liveLayers=L.layerGroup().addTo(liveMap)}
 $('liveCaptains').replaceChildren();const seenCaptains=new Set();
 for(const p of captains){if(Number.isFinite(p.lat)&&Number.isFinite(p.lng)){seenCaptains.add(p.user_id);let marker=liveCaptainMarkers.get(p.user_id);if(marker){marker.setLatLng([p.lat,p.lng]);marker.bindPopup(text('span',`${p.name||'كابتن'} · ${locationLabel(p)} · ${dates(p.location_at)}`));if(marker.setIcon)marker.setIcon(L.divIcon({className:'',html:`<div class="map-marker ${fresh(p)?'':'muted-marker'}"></div>`,iconSize:[20,20]}))}else{marker=captainMarker(p).addTo(liveLayers);liveCaptainMarkers.set(p.user_id,marker)}}$('liveCaptains').append(record(p.name||'كابتن',[['الهاتف',localPhone(p.phone)],['الموقع',locationLabel(p)],['آخر تحديث',dates(p.location_at)],['حالة العمل',p.ride_id?'في رحلة · '+(stateNames[p.ride_status]||p.ride_status):p.in_service===false?'خارج منطقة الخدمة':fresh(p)?'متاح لاستقبال رحلة':'الموقع متأخر؛ تحقق من الاتصال'],['الرحلة',p.ride_id||'—']],[button('إظهار على الخريطة',async()=>{if(p.lat!=null&&p.lng!=null)liveMap.setView([p.lat,p.lng],17)})]))}empty($('liveCaptains'));
 for(const [id,marker]of liveCaptainMarkers)if(!seenCaptains.has(id)){if(liveLayers.removeLayer)liveLayers.removeLayer(marker);liveCaptainMarkers.delete(id)}
 if(activePage==='overview')setTimeout(()=>liveMap.invalidateSize(),0);
}
async function liveSnapshot(){const {data,error}=await db.rpc('tkt_admin_live');if(error)throw error;return data}
function stopLive(){renderCache.clear();requestTracker.clear();if(liveChannel){db.removeChannel(liveChannel);liveChannel=null}clearInterval(liveTimer);clearTimeout(liveEventTimer);liveEventTimer=null;liveTimer=null;$('liveStatus').textContent='غير متصل'}
let liveDirtyPages=new Set(),livePending=false,supportDirty=true,liveAccessDirty=false,pageNeedsRefresh=false;const pageRefreshedAt=new Map();
document.addEventListener('input',event=>{const target=event.target,page=target.closest?.('.page')||target.closest?.('.section-screen');if(page&&(target.closest('form')||['page-pricing','page-coverage','page-staff','page-banners'].includes(page.id))&&target.type!=='search')liveDirtyPages.add(page.dataset.ownerPage||page.id.replace('page-',''));});
async function backgroundRefresh(){if(refreshing||busy||document.hidden||$('admin').hidden){livePending=true;return;}refreshing=true;livePending=false;lastLiveRefresh=Date.now();try{
 if(liveAccessDirty){liveAccessDirty=false;await refreshDashboardAccess();}
 const supportRequested=supportDirty&&canView('support');const supportTask=supportRequested?(supportDirty=false,loadSupport().catch(()=>{supportDirty=true;})):Promise.resolve();
 if(dialogMode==='line')await updateLineTrack();else if(dialogMode==='track')await updateTrack();else if(dialogMode==='chat')await updateChat();else if(dialogMode==='profile')await updateCaptainProfile();
 if(!dialogMode&&!liveDirtyPages.has(activePage)&&!document.activeElement?.closest?.('input:focus,textarea:focus,select:focus')){
 const page=activePage,interval=['overview','rides','lines'].includes(page)?4000:20000;if(pageNeedsRefresh||Date.now()-(pageRefreshedAt.get(page)||0)>=interval){pageNeedsRefresh=false;if(page==='support')await supportTask;if(page==='exchanges'){await exchangesPage.refresh();pageRefreshedAt.set(page,Date.now());}else if(page!=='support'||!supportRequested)await loadPage(page);}
 }
 await supportTask;
 if(!liveChannel)$('liveStatus').textContent='تحديث تلقائي';
}catch(e){$('liveStatus').textContent='إعادة الاتصال…';}finally{refreshing=false;if(livePending)scheduleLiveRefresh();}}
function scheduleLiveRefresh(){livePending=true;if(liveEventTimer)return;liveEventTimer=setTimeout(()=>{liveEventTimer=null;backgroundRefresh()},Math.max(0,400-(Date.now()-lastLiveRefresh)))}
function startLive(){stopLive();liveChannel=db.channel('tkt:dashboard',{config:{private:true}}).on('broadcast',{event:'invalidate'},event=>{const resource=event.payload?.resource;const affected={support:['support_workflow','tkt_messages','tkt_recovery_messages','tkt_recovery_threads','exchange_messages','ride_emergencies'],exchanges:['exchange_agents','exchange_settlements','exchange_transactions'],company:['tkt_payments','company_expenses','exchange_transactions'],pricing:['pricing_settings','booking_prices'],coverage:['dispatch_settings'],staff:['staff_accounts','tkt_admins'],rewards:['coupons','coupon_uses','coupon_history','coupon_card_batches','coupon_captain_rewards'],banners:['tkt_home_banners'],favorites:['tkt_saved_places'],applications:['tkt_captain_applications'],wheel:['wheel_prizes','wheel_settings','wheel_spins']};if(!affected[activePage]||affected[activePage].includes(resource))pageNeedsRefresh=true;if(['support_workflow','exchange_messages','tkt_messages','tkt_recovery_messages','tkt_recovery_threads'].includes(resource))supportDirty=true;if(['staff_accounts','tkt_admins'].includes(resource))liveAccessDirty=true;scheduleLiveRefresh();}).subscribe(value=>{$('liveStatus').textContent=value==='SUBSCRIBED'?'متصل مباشرة':'إعادة الاتصال…';if(value==='SUBSCRIBED')scheduleLiveRefresh();});liveTimer=setInterval(backgroundRefresh,4000);}
document.addEventListener('visibilitychange',()=>{if(!document.hidden)scheduleLiveRefresh();});window.addEventListener('online',()=>scheduleLiveRefresh());
async function loadRides(more=false){const token=requestTracker.next('rides'),scope=[$('rideStatus').value,$('rideSearch').value.trim()].join('|');const data=await manage('rides',{offset:more?rides.length:0,limit:200,status:$('rideStatus').value,search:$('rideSearch').value.trim()});if(!requestTracker.current(token)||scope!==[$('rideStatus').value,$('rideSearch').value.trim()].join('|'))return;rides=more?[...rides,...data]:data;renderRides();$('moreRides').disabled=data.length<200}
function renderRides(){if(!renderCache.changed('rides',[rides,$('rideStatus').value,$('rideSearch').value,rides.some(r=>r.round_trip_stage==='waiting')?Math.floor(serverTime/1000):null]))return;const list=$('rideList');list.replaceChildren();$('rideCount').textContent=`${rides.length} رحلة معروضة`;for(const r of rides){const controls=[button('التفاصيل والتتبع',()=>trackRide(r.id))];if(['pending','accepted','arrived'].includes(r.status))controls.push(button('إلغاء الرحلة',async()=>{if(confirm('إلغاء الرحلة ورد مبلغ المحفظة حسب النظام؟')){await manage('ride_cancel',{id:r.id});await loadRides()}},'danger'));if(!activeStates.includes(r.status))controls.push(button('أرشفة الرحلة',()=>archive('ride',r.id),'danger'));list.append(record(`${r.pickup_name||'انطلاق محدد'} ← ${r.destination_name||'وجهة محددة'}`,[['الحالة',stateNames[r.status]||r.status],...tripFacts(r),['الكروة',money(r.fare)],['الدفع',r.payment_method==='wallet'?'دفع من المحفظة':'دفع كاش'],['الزبون',`${r.rider_name||'—'} · ${localPhone(r.rider_phone)}`],['الكابتن',r.captain_name||'لم يُحدد'],['إنشاء الرحلة',dates(r.created_at)],['مرجع الرحلة',r.id]],controls))}empty(list)}
async function trackRide(id){rideMovingMarker=null;const body=openDetail('تفاصيل الرحلة والتتبع');dialogMode='track';dialogKey=id;body.append(Object.assign(text('div',''),{id:'rideTrackMap',className:'admin-map'}),Object.assign(text('p',''),{id:'rideTrackLegend',className:'notice'}),Object.assign(text('div',''),{id:'rideTrackInfo'}),Object.assign(text('div',''),{id:'rideOffers'}));dialogMap=mapFor('rideTrackMap');dialogLayer=L.layerGroup().addTo(dialogMap);await updateTrack(true)}
async function updateTrack(fit=false){if(dialogRefreshing||dialogMode!=='track')return;dialogRefreshing=true;const epoch=dialogEpoch,id=dialogKey;try{const result=await manage('track',{id});if(epoch!==dialogEpoch||dialogMode!=='track')return;serverTime=Date.parse(result.server_now);const r=result.ride,p=result.captain;const bounds=[];if(renderCache.changed('ride-route:'+epoch,[r.geometry,r.return_geometry,r.pickup,r.destination,r.round_trip_stage])){dialogLayer.clearLayers();rideMovingMarker=null;for(const route of tripMapData(r).lines){const line=L.geoJSON(route.geometry,{style:{color:route.color,weight:5,dashArray:route.dashArray}}).bindPopup(text('span',route.label)).addTo(dialogLayer);bounds.push(...line.getBounds().isValid()?[line.getBounds().getSouthWest(),line.getBounds().getNorthEast()]:[])}for(const [point,label]of tripMapData(r).points)if(Array.isArray(point)){L.circleMarker(point,{radius:8,color:'#d92527',fillOpacity:1}).bindPopup(text('span',label)).addTo(dialogLayer);bounds.push(point)}}if(p&&Number.isFinite(p.lat)&&Number.isFinite(p.lng)){if(rideMovingMarker){rideMovingMarker.setLatLng([p.lat,p.lng]);if(rideMovingMarker._fresh!==fresh(p)&&rideMovingMarker.setIcon)rideMovingMarker.setIcon(L.divIcon({className:'',html:`<div class="map-marker ${fresh(p)?'':'muted-marker'}"></div>`,iconSize:[20,20]}));}else{rideMovingMarker=captainMarker(p).addTo(dialogLayer);}rideMovingMarker._fresh=fresh(p);rideMovingMarker.bindPopup(text('span',`${p.name||'كابتن'} · ${locationLabel(p)}`));bounds.push([p.lat,p.lng]);}else if(rideMovingMarker){dialogLayer.removeLayer(rideMovingMarker);rideMovingMarker=null;}
 if(fit&&bounds.length)dialogMap.fitBounds(bounds,{padding:[30,30],maxZoom:17});
 $('rideTrackInfo').replaceChildren(facts([['مرجع الرحلة',r.id],['الحالة',stateNames[r.status]||r.status],...tripFacts(r,true),['الانطلاق',r.pickup_name||'نقطة محددة'],['الوجهة',r.destination_name||'نقطة محددة'],['الكروة',money(r.fare)],['الخصم',money(r.discount||0)],['المطلوب من الزبون',money(r.customer_due??r.fare)],['طريقة الدفع',r.payment_method==='wallet'?'دفع من المحفظة':'دفع كاش'],['مسافة الطريق',((r.distance_m||0)/1000).toFixed(2)+' كم'],[r.round_trip?'مدة المشوار المقدرة مع الانتظار':'مدة الطريق المقدرة',Math.ceil((r.duration_s||0)/60)+' دقيقة'],['إنشاء الرحلة',dates(r.created_at)],['آخر تعديل',dates(r.updated_at)]]),p?facts([['الكابتن',p.name],['هاتف الكابتن',localPhone(p.phone)],['تحديث الموقع',locationLabel(p)],['آخر موقع GPS',dates(p.location_at)]]):text('p','لم يوافق كابتن بعد'));

 const legend=$('rideTrackLegend');if(legend)legend.textContent=r.round_trip?(r.round_trip_stage==='returning'?'الأحمر: مسار الرجعة الحالي':'الأحمر: مسار الذهاب · الأزرق المتقطع: مسار الرجعة'):'الأحمر: مسار الرحلة';
 $('rideOffers').replaceChildren(text('h3','عروض توزيع الطلب'));for(const o of result.offers)$('rideOffers').append(text('p',`${o.captain_name||o.captain_id} · ${localPhone(o.captain_phone)} · وصول مقدر ${o.eta_s==null?"—":Math.ceil(o.eta_s/60)+" دقيقة"} · ${{offered:'بانتظار الرد',accepted:'تم القبول',expired:'انتهت المهلة',rejected:'مرفوض',cancelled:'ملغي'}[o.status]||o.status} · أنشئ ${dates(o.created_at)} · ينتهي ${dates(o.expires_at)} · المتبقي ${Math.max(0,Math.min(30,Math.ceil((Date.parse(o.expires_at)-serverTime)/1000)))||0} ثانية`));
 }finally{dialogRefreshing=false}}
async function loadUsers(more=false){const token=requestTracker.next('users'),scope=$('userSearch').value.trim();const data=await manage('users',{offset:more?users.length:0,limit:200,search:$('userSearch').value.trim()});if(!requestTracker.current(token)||scope!==$('userSearch').value.trim())return;users=more?[...users,...data]:data;renderUsers();$('moreUsers').disabled=data.length<200}
async function userAction(action,data){await manage(action,data);await loadUsers();status('تم تحديث الحساب')}
function renderUsers(){if(!renderCache.changed('users',[users.map(({lat,lng,location_at,...row})=>row),$('userSearch').value]))return;$('userList').replaceChildren();for(const u of users){const controls=[...(dashboardAccess?.owner===true?[button('حذف الحساب',()=>accountAdmin.open('user',u.user_id),'danger')]:[]),button('عرض الملف الشخصي',()=>openUserProfile(u.user_id)),button('تعديل البيانات',()=>editUser(u)),button('المحفظة والسجل',()=>ledger(u)),button('تعيين كلمة سر',()=>resetPassword(u))];if(!u.admin){controls.push(button(u.captain?'إلغاء صلاحية كابتن':'تفعيل كابتن',async()=>{if(confirm('تأكيد تغيير نوع الحساب؟'))await userAction('role',{user_id:u.user_id,captain:!u.captain})}),button(u.blocked?'رفع الحظر':'حظر',async()=>{if(confirm('تأكيد تغيير الحظر؟'))await userAction('block',{user_id:u.user_id,blocked:!u.blocked})}),button('أرشفة الحساب',()=>archive('user',u.user_id),'danger'));if(u.captain)controls.push(button('تجديد 7 أيام — 5,000 د.ع',async()=>{if(confirm('تأكيد تسجيل دفعة وتجديد الاشتراك؟'))await userAction('renew',{user_id:u.user_id,payment_id:crypto.randomUUID()})}),button('تعديل انتهاء الاشتراك',()=>editSubscription(u)))}$('userList').append(record(u.name||'بدون اسم',[['الهاتف',localPhone(u.phone)],['نوع الحساب',u.admin?'إدارة':u.captain?'كابتن':'زبون'],['الحساب',u.blocked?'محظور':'فعال'],['استقبال الطلبات',u.captain?(u.online?'مفعّل':'متوقف'):'—'],['الاشتراك',u.captain?dates(u.expires_at):'—']],controls))}empty($('userList'))}
function editUser(u){const body=openDetail('تعديل بيانات الحساب'),name=inputField('الاسم الكامل',u.name),phone=inputField('رقم الهاتف',localPhone(u.phone),'tel');body.append(name.box,phone.box,button('حفظ',async()=>{await manage('user_edit',{user_id:u.user_id,name:name.input.value,phone:phone.input.value});closeDetail();await loadUsers();status('تم حفظ البيانات')}))}
function editSubscription(u){const body=openDetail('تعديل نهاية الاشتراك'),expiry=inputField('نهاية الاشتراك بتوقيت بغداد',toLocal(u.expires_at),'datetime-local');body.append(expiry.box,button('حفظ',async()=>{await manage('subscription_edit',{user_id:u.user_id,expires_at:baghdadISO(expiry.input.value)});closeDetail();await loadUsers()}))}
function toLocal(date){return date?new Date(Date.parse(date)+3*3600000).toISOString().slice(0,16):''}
function baghdadISO(value){if(!value)throw new Error('حدد التاريخ والوقت');return new Date(value+'+03:00').toISOString()}
async function archive(kind,id){if(!confirm(kind==='user'?'إيقاف الحساب وإزالته من القائمة؟ تبقى سجلات الرحلات والأموال محفوظة.':'أرشفة وإزالة هذا السجل من القائمة؟ يمكن استرجاعه من الأرشيف.'))return;await manage('archive',{kind,entity_id:id});closeDetail();await loadPage(activePage);status('تمت الأرشفة')}
async function loadFinance(){finance=await manage('finance');renderWallets()}
function renderWallets(){const list=$('walletList');list.replaceChildren();const search=$('walletSearch').value.trim();for(const u of (finance.wallets||[]).filter(u=>`${u.name} ${localPhone(u.phone)}`.includes(search))){const controls=[button('عرض الملف الشخصي',()=>openUserProfile(u.user_id)),button('شحن المحفظة',()=>moneyAction(u,'topup')),button('كشف الحساب',()=>ledger(u))];if(u.captain)controls.push(button('تسديد مستحقات الكابتن',()=>moneyAction(u,'settle')));if(u.captain_requested_at)controls.push(button('مراجعة تسجيل المركبة',async()=>{showPage('applications');await loadApplications()}));list.append(record(u.name||u.phone,[['الهاتف',localPhone(u.phone)],['نوع الحساب',u.captain?'كابتن':'زبون'],[u.captain?'مستحقات الكابتن':'رصيد المحفظة',money(u.balance||0)],['طلب تسجيل كابتن',dates(u.captain_requested_at)]],controls))}empty(list)}
function moneyAction(u,op){const body=openDetail(op==='topup'?'شحن محفظة':'تسجيل تسديد مستحقات'),amount=inputField('المبلغ بالدينار','','number'),id=crypto.randomUUID();amount.input.min=1;amount.input.max=10000000;body.append(text('p',`${u.name} · ${localPhone(u.phone)}`),amount.box,button('تأكيد العملية',async()=>{const value=Number(amount.input.value);if(!Number.isInteger(value)||value<1||value>10000000)throw new Error('أدخل مبلغاً صحيحاً');if(!confirm(`تأكيد ${money(value)}؟`))return;await manage(op,{user_id:u.user_id,amount:value,id});closeDetail();await loadFinance();status('تم تسجيل العملية المالية')}))}
async function ledger(u){const data=await manage('ledger',{user_id:u.user_id,limit:500});openLedger={...data,user:u};const body=openDetail('كشف الحساب');body.append(text('p',`${u.name||''} · ${localPhone(u.phone)} · الرصيد ${money(data.balance||0)}`));const table=document.createElement('table');const head=document.createElement('thead'),row=document.createElement('tr');for(const title of['الوقت','النوع','المبلغ','الرحلة'])row.append(text('th',title));head.append(row);table.append(head);const tbody=document.createElement('tbody');for(const e of data.entries){const tr=document.createElement('tr');for(const v of[dates(e.created_at),ledgerNames[e.kind]||e.kind,money(e.amount),e.ride_id||'—'])tr.append(text('td',v));tbody.append(tr)}table.append(tbody);const wrap=text('div','');wrap.className='table-wrap';wrap.append(table);body.append(wrap,text('h3','مدفوعات الاشتراك'));for(const p of data.payments)body.append(text('p',`${money(p.amount)} · ${dates(p.created_at)} · الاشتراك حتى ${dates(p.expires_at)}`));body.append(button('تصدير CSV',async()=>exportLedger()))}
function exportLedger(){if(!openLedger)return status('افتح كشف حساب أولاً');const escape=v=>'"'+String(v??'').replace(/"/g,'""').replace(/^[=+@-]/,"'")+'"';const rows=[['وقت','نوع','مبلغ','رحلة'],...openLedger.entries.map(e=>[e.created_at,e.kind,e.amount,e.ride_id])];const url=URL.createObjectURL(new Blob(['\ufeff'+rows.map(r=>r.map(escape).join(',')).join('\n')],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='taktooka-ledger.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}

let emergencies=[];
async function emergencyRpc(action,data={}){const {data:result,error}=await db.rpc('tkt_emergency',{p_action:action,p_data:data});if(error)throw error;return result;}
const emergencySources={rider:'موقع الزبون',rider_last_known:'آخر موقع معروف للزبون',vehicle:'موقع مركبة الرحلة',vehicle_last_known:'آخر موقع معروف للمركبة',unavailable:'الموقع غير متاح'};
function emergencyMap(e){return Number.isFinite(e.lat)&&Number.isFinite(e.lng)?`https://maps.google.com/?q=${e.lat},${e.lng}`:null;}
function emergencyText(e){return `SOS حالة طارئة 911\nرقم الرحلة: ${e.ride_id}\nالزبون: ${e.rider_name||'—'} · ${localPhone(e.rider_phone)}\nالكابتن: ${e.captain_name||'—'} · ${localPhone(e.captain_phone)}\nوقت البلاغ: ${dates(e.created_at)}\n${emergencySources[e.location_source]||e.location_source} · ${dates(e.location_at)}\n${emergencyMap(e)||'الموقع غير متاح'}`;}
async function shareEmergency(e){const value=emergencyText(e);if(navigator.share){try{await navigator.share({title:'SOS حالة طارئة 911',text:value});return;}catch(err){if(err.name==='AbortError')return;}}await navigator.clipboard.writeText(value);status('تم نسخ البلاغ للمشاركة مع الطوارئ');}
function emergencyActions(e){const actions=[button('مشاركة البلاغ مع الطوارئ',()=>shareEmergency(e)),button('نسخ البلاغ',async()=>{await navigator.clipboard.writeText(emergencyText(e));status('تم نسخ البلاغ')}),button('اتصال بـ911',()=>{window.location.href='tel:911'})];const map=emergencyMap(e);if(map)actions.unshift(button('فتح الموقع',()=>window.open(map,'_blank','noopener,noreferrer')));if(e.status==='open'&&canEdit('support'))actions.push(button('تم التعامل مع الحالة',async()=>{if(!confirm('تم التواصل والتعامل مع الحالة الطارئة؟'))return;await emergencyRpc('resolve',{id:e.id});emergencyAlarm.resolved(e.id);await loadEmergencies();}));return actions;}
async function loadEmergencies(){const token=requestTracker.next('emergencies'),rows=await emergencyRpc('list');if(!requestTracker.current(token))return;emergencies=rows;renderSupport();await emergencyAlarm.refresh();}
async function openEmergency(id){showPage('support');await loadSupport();const e=emergencies.find(e=>e.id===id);if(e){const body=openDetail('SOS حالة طارئة 911');body.append(text('p',emergencyText(e)),...emergencyActions(e));}}
let supportLoading=null;let exchangeRooms=[],supportRooms=[], supportSearch='', supportFilter='all';
async function supportRpc(action,data={}){return dashboardRpc('tkt_support',action,data);}
async function loadSupport(){if(supportLoading)return supportLoading;supportLoading=(async()=>{const token=requestTracker.next('support');const [rooms,threads,agents,workflow]=await Promise.all([manage('support_rooms'),manage('recovery'),supportRpc('rooms'),dashboardRpc('tkt_operations','workflow'),loadEmergencies()]);if(!requestTracker.current(token))return;supportRooms=rooms;recovery=threads;exchangeRooms=agents;operations.setWorkflow(workflow);renderSupport();pageRefreshedAt.set('support',Date.now());})().finally(()=>{supportLoading=null;});return supportLoading;}
function renderSupport(){if(!renderCache.changed('support',[supportRooms,recovery,exchangeRooms,emergencies,supportSearch,supportFilter,operations.workflow]))return;
 const q=supportSearch.toLowerCase(),list=$('supportRooms');list.replaceChildren();$('recoveryRooms').replaceChildren();$('recoveryRooms').hidden=true;$('recoveryHeading').hidden=true;$('supportHeading').textContent='كل المحادثات والبلاغات';
 const rooms=[...supportRooms.map(r=>({...r,kind:'support'})),...recovery.map(r=>({...r,kind:'recovery'})),...exchangeRooms.map(r=>({...r,kind:'exchange'})),...emergencies.map(r=>({...r,kind:'emergency',name:r.rider_name||'بلاغ طوارئ',phone:r.rider_phone,last_at:r.created_at}))].sort((a,b)=>(Date.parse(b.last_at||b.created_at)||0)-(Date.parse(a.last_at||a.created_at)||0)||String(a.id||a.user_id).localeCompare(String(b.id||b.user_id)));
 for(const r of rooms.filter(r=>`${r.name||''} ${r.personal_name||''} ${r.captain_name||''} ${r.ride_id||''} ${localPhone(r.phone)} ${localPhone(r.captain_phone)}`.toLowerCase().includes(q)).filter(r=>supportFilter==='all'||supportFilter==='unread'&&r.unread>0||supportFilter===r.kind).filter(r=>operations.matches(r))){
 if(r.kind==='emergency'){const row=text('article','');row.className='support-conversation';const open=text('button','');open.type='button';open.className='conversation-open';const avatar=text('span','SOS');avatar.className='support-avatar';const summary=text('span','');summary.className='support-summary';summary.append(text('strong',r.rider_name||'بلاغ طوارئ 911'),text('span','بلاغ طوارئ SOS · '+localPhone(r.rider_phone)),text('small',dates(r.created_at)));const state=text('span',r.status==='open'?'طارئ':'تم التعامل');state.className=r.status==='open'?'unread-count':'conversation-state';open.append(avatar,summary,state);open.setAttribute('aria-label','فتح تفاصيل بلاغ الطوارئ '+(r.rider_name||''));open.onclick=()=>run(()=>openEmergency(r.id));row.append(open);list.append(row);continue;}
 const kind=r.kind,row=text('article','');row.className='support-conversation';const open=document.createElement('button');open.type='button';open.className='conversation-open';
 const avatar=text('span',kind==='exchange'?'⇄':(r.name||'م').trim().slice(0,1));avatar.className='support-avatar';
 const summary=text('span','');summary.className='support-summary';summary.append(text('strong',r.name||localPhone(r.phone)),text('span',({support:'دعم التطبيق',recovery:'استرجاع حساب',exchange:'دعم الصيرفات'})[kind]+' · '+localPhone(r.phone)),text('small',dates(r.last_at||r.created_at)));
 const unread=text('span',r.unread>0?String(r.unread):'فتح');unread.className=r.unread>0?'unread-count':'conversation-state';open.append(avatar,summary,unread);open.onclick=()=>run(()=>chat(kind,r));row.append(open);
 summary.append(text('small',operations.supportLabel(r)));const actions=text('div','');actions.className='conversation-actions';actions.append(button('إسناد وحالة المحادثة',()=>operations.editWorkflow(r)));if(kind==='recovery')actions.append(button('تعيين كلمة سر',()=>resetPassword(r)));if(kind!=='exchange')actions.append(button('أرشفة',()=>archive(kind,kind==='support'?r.user_id:r.id)));row.append(actions);list.append(row);
 }empty(list);
 const count=rooms.reduce((n,r)=>n+Number(r.unread||0),0);const tab=document.querySelector('[data-page="support"]');if(tab)tab.textContent='الدعم والاسترجاع'+(count?' ('+count+')':'');
}
async function openExchangeSupport(room){if(!canView('support'))throw new Error('PERMISSION_DENIED');showPage('support');await loadSupport();await chat('exchange',{...room,id:room.id});}
$('supportSearch').oninput=e=>{supportSearch=e.target.value.trim();renderSupport()};$('supportFilter').onchange=e=>{supportFilter=e.target.value;renderSupport()};$('chatBack').onclick=()=>requestAppBack(closeDetail);
function appendLinks(element,body){const pattern=/https?:\/\/[^\s<>]+/g;let end=0;for(const match of body.matchAll(pattern)){element.append(document.createTextNode(body.slice(end,match.index)));const a=text('a',match[0]);a.href=match[0];a.target='_blank';a.rel='noopener noreferrer';element.append(a);end=match.index+match[0].length;}element.append(document.createTextNode(body.slice(end)));}
async function chat(kind,room){
 closeDetail();dialogMode='chat';dialogKey={kind,room};const epoch=dialogEpoch;
 $('chatTitle').textContent=room.name||'محادثة الدعم';$('chatSubtitle').textContent=(kind==='recovery'?'استرجاع الحساب':kind==='exchange'?'دعم الصيرفات':'دعم التطبيق')+' · '+localPhone(room.phone||'');$('chatScreen').hidden=false;document.body.classList.add('chat-open');setMenu(false);
 const body=$('chatWorkspace');body.replaceChildren();const log=Object.assign(text('div',''),{id:'chatLog',className:'chat-log'});log.setAttribute('role','log');log.setAttribute('aria-live','polite');log.append(text('p','جاري تحميل المحادثة…'));body.append(log);
 const form=document.createElement('form');form.className='chat-compose';const input=document.createElement('textarea');input.id='chatInput';input.placeholder='اكتب رسالتك… Enter للإرسال، Shift+Enter لسطر جديد';input.setAttribute('aria-description','Enter للإرسال وShift+Enter لسطر جديد');input.setAttribute('aria-label','نص الرد');input.required=true;input.maxLength=2000;input.rows=1;
 const send=text('button','إرسال');send.type='submit';send.disabled=!canEdit('support');input.disabled=!canEdit('support');if(!canEdit('support'))input.placeholder='صلاحيتك لعرض المحادثة فقط';const error=text('p','');error.className='chat-error';error.setAttribute('role','alert');let pending=null;form.append(input,send,error);
 form.onsubmit=async e=>{e.preventDefault();const bodyText=input.value.trim();if(!bodyText||send.disabled)return;pending=pending?.body===bodyText?pending:{id:crypto.randomUUID(),body:bodyText};send.disabled=true;error.textContent='';try{
 if(kind==='exchange')await supportRpc('send',{agent_id:room.id,id:pending.id,body:bodyText});else if(kind==='support')await manage('send',{user_id:room.user_id,id:pending.id,body:bodyText});else await manage('recovery_send',{id:room.id,message_id:pending.id,body:bodyText});if(epoch!==dialogEpoch)return;if(input.value.trim()===bodyText)input.value='';pending=null;await updateChat();log.scrollTop=log.scrollHeight;
 }catch(e){if(epoch===dialogEpoch)error.textContent=message(e)}finally{send.disabled=false;}};
 body.append(form);input.focus();try{await updateChat()}catch(e){if(epoch===dialogEpoch){log.replaceChildren(text('p','تعذّر تحميل المحادثة.'));error.textContent=message(e)}}
}
async function updateChat(){if(dialogRefreshing||dialogMode!=='chat')return;dialogRefreshing=true;const epoch=dialogEpoch,{kind,room}=dialogKey;try{
 const rows=kind==='exchange'?await supportRpc('read',{agent_id:room.id}):kind==='support'?await manage('read',{user_id:room.user_id}):await manage('recovery_messages',{id:room.id});if(epoch!==dialogEpoch||dialogMode!=='chat')return;const sig=rows.map(m=>m.id).join(',');if(sig===chatSignature)return;const first=chatSignature===null;chatSignature=sig;supportDirty=true;scheduleLiveRefresh();
 const log=$('chatLog'),nearBottom=first||log.scrollHeight-log.scrollTop-log.clientHeight<60;log.replaceChildren();let day='';
 for(const m of rows){const date=new Date(m.created_at).toLocaleDateString('ar-IQ',{timeZone:'Asia/Baghdad'});if(date!==day){const label=text('span',date);label.className='chat-day';log.append(label);day=date;}
 const box=text('div','');box.className='chat-message'+(m.is_admin?' admin-message':'');const content=text('div','');content.className='message-content';appendLinks(content,m.body||'');box.append(content,text('small',`${m.is_admin?'الدعم':room.name||'المستخدم'} · ${displayTime(m.created_at)}`));log.append(box);
 }if(!rows.length)log.append(text('p','ابدأ المحادثة بإرسال رسالة.'));if(nearBottom)log.scrollTop=log.scrollHeight;
 }finally{dialogRefreshing=false}}
function setMenu(open,record=true){if(record)navigationWillChange();const menu=$('dashboardMenu');if(open&&!$('admin').hidden){if(!menu.open)menu.showModal();}else if(menu.open)menu.close();document.body.classList.toggle('menu-open',menu.open);$('menuBackdrop').hidden=true;$('menuToggle').setAttribute('aria-expanded',String(menu.open));if(record)navigationChanged();}
$('menuToggle').onclick=()=>setMenu(!document.body.classList.contains('menu-open'));$('menuBackdrop').onclick=()=>setMenu(false);document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!$('dashboardMenu').open){if(dialogMode==='chat'&&!document.querySelector('dialog[open]')){e.preventDefault();requestAppBack(closeDetail)}}});
function resetPassword(u){const body=openDetail('رابط استعادة كلمة السر');body.append(text('p',`الحساب: ${u.name||''} · ${localPhone(u.phone)}. تحقق من صاحب الرقم قبل إنشاء الرابط. الرابط صالح 30 دقيقة ولمرة واحدة.`),button('إنشاء رابط آمن',async()=>{const {data,error}=await db.functions.invoke('taktooka-password-link',{body:{op:'issue',user_id:u.user_id,phone:u.phone}});if(error||!data?.url)throw new Error(data?.error||'تعذر إنشاء الرابط');body.replaceChildren(text('p','تم إنشاء الرابط؛ إنشاء رابط جديد يلغي السابق.'),text('p','أرسله فقط إلى رقم صاحب الحساب المسجّل.'));const phone=normalizeWhatsAppPhone(data.phone);if(!phone)throw Error('رقم الهاتف غير صالح لفتح واتساب');const whatsapp=document.createElement('a');whatsapp.textContent='فتح واتساب لإرسال الرابط';whatsapp.href='https://wa.me/'+phone+'?text='+encodeURIComponent('تكتوكة 🛺\nهذا رابط تعيين كلمة سر جديدة لحسابك، صالح 30 دقيقة ولمرة واحدة. لا تشاركه ويا أحد:\n'+data.url);whatsapp.target='_blank';whatsapp.rel='noopener noreferrer';whatsapp.className='button';body.append(whatsapp,button('نسخ الرابط',async()=>{await navigator.clipboard.writeText(data.url);status('تم نسخ رابط استعادة كلمة السر');}));}));}
async function loadFavorites(){favorites=await manage('favorites',{limit:500});renderFavorites()}
function renderFavorites(){const list=$('favoriteList');list.replaceChildren();const q=$('favoriteSearch').value.trim();for(const f of favorites.filter(f=>`${f.label} ${f.name} ${localPhone(f.phone)}`.includes(q)))list.append(record(f.label,[['المستخدم',f.name],['الهاتف',localPhone(f.phone)],['خط العرض',f.lat],['خط الطول',f.lng]],[button('تعديل',()=>editFavorite(f)),button('حذف',async()=>{if(confirm('حذف العنوان المفضل من حساب المستخدم؟')){await manage('favorite_delete',{id:f.id});await loadFavorites()}},'danger')]));empty(list)}
function editFavorite(f){const body=openDetail('تعديل العنوان المفضل'),label=inputField('اسم العنوان',f.label),lat=inputField('خط العرض',f.lat,'number'),lng=inputField('خط الطول',f.lng,'number');lat.input.step=lng.input.step='any';body.append(label.box,lat.box,lng.box,Object.assign(text('div',''),{id:'favoriteMap',className:'admin-map'}),button('حفظ',async()=>{await manage('favorite_edit',{id:f.id,label:label.input.value,lat:Number(lat.input.value),lng:Number(lng.input.value)});closeDetail();await loadFavorites()}));dialogMap=mapFor('favoriteMap');dialogMap.setView([f.lat,f.lng],17);const marker=L.marker([f.lat,f.lng],{draggable:true}).addTo(dialogMap);const set=p=>{lat.input.value=p.lat;lng.input.value=p.lng;marker.setLatLng(p)};marker.on('dragend',()=>set(marker.getLatLng()));dialogMap.on('click',e=>set(e.latlng))}
async function loadSecurity(){security=await manage('security');$('securityList').replaceChildren();for(const p of security)$('securityList').append(record(localPhone(p.phone),[['طلبات النافذة',p.requests+' / 40'],['بداية النافذة',dates(p.window_at)],['حالة النافذة',Date.now()-Date.parse(p.window_at)<900000?'جارية لمدة 15 دقيقة':'انتهت؛ العداد تاريخي'],['كلمة المرور الخاطئة','لا تحظر الحساب']],[button('فتح المحاولات',async()=>{if(confirm('فتح محاولات الدخول لهذا الرقم؟')){await manage('unlock_phone',{phone:p.phone});await loadSecurity()}})]));empty($('securityList'))}
async function loadAudit(){[audit,archives]=await Promise.all([manage('audit',{limit:500}),manage('archives',{limit:500})]);$('auditList').replaceChildren();for(const a of audit){const row=record(`${a.actor_name||a.actor_id} · ${actionNames[a.action]||a.action}`,`${a.entity_id||''} · ${dates(a.created_at)}`),details=text('details',''),summary=text('summary','تفاصيل العملية');details.append(summary,Object.assign(text('pre',JSON.stringify(a.details,null,2)),{className:'audit-details'}));row.append(details);$('auditList').append(row)}empty($('auditList'));$('archiveList').replaceChildren();for(const a of archives)$('archiveList').append(record(`${archiveNames[a.kind]||a.kind} · ${a.entity_id}`,dates(a.created_at),[button('استرجاع',async()=>{if(confirm('استرجاع السجل إلى القائمة؟')){await manage('restore',{kind:a.kind,entity_id:a.entity_id});await loadAudit()}})]));empty($('archiveList'))}
async function loadPage(name){if(name==='commerce')return commercePage.load();if(name==='restaurant-support')return commercePage.complaints();pageRefreshedAt.set(name,Date.now());if(name==='server')return serverMonitor.load();if(name==='exchanges')return exchangesPage.load();if(name==='rewards')return couponRewards.load();if(name==='company')return companyPage.load();if(name==='lines')return loadLines();if(name==='inventory')return loadInventory();if(name==='staff')return loadStaff();if(name==='pricing')return loadPricing();if(name==='coverage'){settings=await rpc('settings');zones=structuredClone(settings.zones);initMap();$('search').value=settings.search_s;$('eta').value=settings.max_eta_s/60;$('stale').value=settings.stale_s;render();return;}if(name==='wheel')return loadWheel();if(name==='banners')return loadBanners();if(name==='applications')return loadApplications();if(name==='overview')return loadOverview();if(name==='rides')return loadRides();if(name==='users')return loadUsers();if(name==='finance')return loadFinance();if(name==='support')return loadSupport();if(name==='favorites')return loadFavorites();if(name==='security')return loadSecurity();if(name==='audit')return loadAudit()}
async function navigatePage(name){const epoch=++navigationEpoch;try{showPage(name);status('جاري تحديث البيانات…');await loadPage(name);if(epoch!==navigationEpoch||activePage!==name)return;applyDashboardPermissions();if(name==='overview'&&liveMap)requestAnimationFrame(()=>liveMap.invalidateSize());status('تم تحديث البيانات');}catch(e){if(epoch===navigationEpoch)status(message(e));}}
for(const el of document.querySelectorAll('[data-page]'))el.onclick=()=>navigatePage(el.dataset.page);
for(const [id,fn]of[['refreshOverview',loadOverview],['reloadRides',loadRides],['reloadUsers',loadUsers],['refreshFinance',loadFinance],['refreshSupport',loadSupport],['refreshFavorites',loadFavorites],['refreshSecurity',loadSecurity],['refreshAudit',loadAudit]])$(id).onclick=()=>run(()=>fn());
$('moreRides').onclick=()=>run(()=>loadRides(true));$('moreUsers').onclick=()=>run(()=>loadUsers(true));
for(const [id,fn,key]of[['rideSearch',loadRides,'rides'],['userSearch',loadUsers,'users']]){const search=debounceTask(()=>fn().catch(e=>{if(activePage===key)status(message(e));}),250);$(id).oninput=()=>{requestTracker.invalidate(key);search();};}
$('rideStatus').onchange=()=>run(()=>loadRides());$('walletSearch').oninput=renderWallets;$('favoriteSearch').oninput=renderFavorites;$('exportLedger').onclick=exportLedger;


const applicationNames={pending:'قيد المراجعة',changes_required:'يحتاج تعديل',approved:'تمت الموافقة'};
const documentLabels={id_front:'وجه الجنسية',id_back:'خلف الجنسية',residence_front:'وجه بطاقة السكن',residence_back:'خلف بطاقة السكن',selfie:'صورة فحص الوجه',portrait:'صورة البروفايل'};
let applications=[];
async function applicationRpc(action,data={}){const result=await db.rpc('tkt_captain_registration',{p_action:action,p_data:data});if(result.error)throw result.error;return result.data}
async function loadApplications(more=false){if(!more)await loadPortalSettings();const token=requestTracker.next('applications'),scope=[$('applicationStatus').value,$('applicationSearch').value.trim()].join('|');const rows=await applicationRpc('list',{status:$('applicationStatus').value,search:$('applicationSearch').value.trim(),limit:100,offset:more?applications.length:0});if(!requestTracker.current(token)||scope!==[$('applicationStatus').value,$('applicationSearch').value.trim()].join('|'))return;applications=more?[...applications,...rows]:rows;if(!renderCache.changed('applications',[applications,scope]))return;const list=$('applicationList');list.replaceChildren();for(const a of applications)list.append(record(a.full_name,`${localPhone(a.phone)} · ${applicationNames[a.status]||a.status} · ${a.province||'—'} — ${a.area||'—'} · ${dates(a.submitted_at)}`,[button('عرض الملف الشخصي',()=>openUserProfile(a.user_id)),button('التفاصيل والمستمسكات',()=>applicationDetail(a))]));empty(list);$('moreApplications').hidden=rows.length<100}
async function applicationDetail(a){
 const body=openDetail('تسجيل المركبات — '+a.full_name),epoch=dialogEpoch;
 const details=text('div','');details.className='application-summary';
 for(const [label,value]of [['الاسم الكامل',a.full_name],['رقم الهاتف',localPhone(a.phone)],['المحافظة',a.province],['المنطقة',a.area],['نظام العمل',a.work_plan==='commission'?'نظام النسبة':'اشتراك أسبوعي'],['المركبة',a.vehicle_kind==='bike'?'دراجة':'تكتك'],['حالة الطلب',applicationNames[a.status]],['تاريخ الإرسال',dates(a.submitted_at)],['تاريخ المراجعة',dates(a.reviewed_at)],['نسخة الطلب',a.revision]])details.append(text('p',`${label}: ${value??'—'}`));

 if(a.reason)details.append(text('p','التعديل المطلوب: '+a.reason));body.append(details);
 const gallery=text('div','');gallery.className='application-documents';body.append(gallery);
 for(const [slot,label]of Object.entries(documentLabels)){
  if(!a.documents?.[slot]&&!['id_front','id_back'].includes(slot))continue;
  const card=text('figure',''),caption=text('figcaption',label);card.append(caption);gallery.append(card);
  const path=a.documents?.[slot];if(!path){card.append(text('p','الصورة غير متاحة'));continue}
  const {data,error}=await db.storage.from('captain-documents').createSignedUrl(path,600);
  if(epoch!==dialogEpoch)return;
  if(error||!data?.signedUrl){card.append(text('p','تعذّر عرض الصورة. أغلق التفاصيل وافتحها مجدداً.'));continue}
  const link=document.createElement('a');link.href=data.signedUrl;link.target='_blank';link.rel='noopener noreferrer';const img=document.createElement('img');img.src=data.signedUrl;img.alt=label;img.referrerPolicy='no-referrer';link.append(img);card.append(link);
 }
 if(a.status!=='pending')return;
 const form=document.createElement('form'),label=text('label','التعديل المطلوب عند رفض الطلب'),reason=document.createElement('textarea');reason.id='applicationReason';reason.maxLength=2000;reason.rows=3;reason.placeholder='اكتب السبب وما يحتاج الكابتن تعديله';label.append(reason);form.append(label);
 async function review(decision){const why=reason.value.trim();if(decision==='changes_required'&&why.length<3){reason.focus();throw new Error('اكتب سبب الرفض والتعديل المطلوب')}if(decision==='approved'&&!confirm('الموافقة على المستمسكات وتفعيل حساب الكابتن؟'))return;await applicationRpc('review',{user_id:a.user_id,revision:a.revision,decision,reason:why});closeDetail();await loadApplications();status(decision==='approved'?'تمت الموافقة وتفعيل حساب الكابتن':'تم إرسال سبب التعديل للكابتن')}
 form.onsubmit=e=>{e.preventDefault();run(()=>review('changes_required'))};const actions=text('div','');actions.className='controls';actions.append(button('موافقة وتفعيل الكابتن',()=>review('approved'),'approve'),button('رفض لغرض التعديل',()=>review('changes_required'),'danger'));form.append(actions);body.append(form);
}
$('refreshApplications').onclick=()=>run(()=>loadApplications());$('moreApplications').onclick=()=>run(()=>loadApplications(true));$('applicationStatus').onchange=()=>run(()=>loadApplications());$('applicationSearch').onchange=()=>run(()=>loadApplications());

let notificationChannel,notificationTimer,notificationRows=[],notificationUser,webMessaging,webToken,webRegistration,webMessageUnsubscribe,pushInitializing;
let notificationEpoch=0,noticeRequest=0;
const notified=new Set();
const observedNotices=new Set();
let noticesInitialized=false;
const pushStorageKey='taktooka-admin-push';
function savedPush(){try{return JSON.parse(localStorage.getItem(pushStorageKey)||'null')}catch(_){return null}}
function rememberPush(value){try{if(value)localStorage.setItem(pushStorageKey,JSON.stringify(value));else localStorage.removeItem(pushStorageKey)}catch(_){}}
function pushState(label,error=''){$('enableNotifications').textContent=label;$('enableNotifications').title=error;}
function validNotice(n){return n.kind!=='offer_end'&&(!n.expires_at||Date.parse(n.expires_at)>Date.now());}
async function showDeviceNotice(n){
 if(notificationUser&&n.user_id===notificationUser&&validNotice(n)&&!notified.has(n.id))playNoticeSound(n.id);
 if(!notificationUser||n.user_id!==notificationUser||!validNotice(n)||notified.has(n.id)||globalThis.Notification?.permission!=='granted')return;
 const epoch=notificationEpoch;notified.add(n.id);
 try{const registration=webRegistration||await navigator.serviceWorker?.getRegistration(new URL('./',location.href).href);
  if(epoch!==notificationEpoch)return;
  const options={body:englishDigits(n.body),tag:n.id,silent:false,renotify:true,vibrate:[180,80,180],icon:new URL('./assets/logo.png',location.href).href,data:{notification_id:n.id,recipient_id:n.user_id,target:n.target||{}}};
  if(registration)await registration.showNotification(englishDigits(n.title),options);
  else{const popup=new Notification(englishDigits(n.title),options);popup.onclick=()=>{window.focus();run(()=>openNotification(n));popup.close();};}
 }catch(_){notified.delete(n.id);}
}
async function waitForPushWorker(registration){
 if(!registration.installing&&!registration.waiting&&registration.active?.state==='activated')return;
 const worker=registration.installing||registration.waiting||registration.active;
 if(!worker)throw new Error('تعذّر تشغيل خدمة إشعارات الخلفية');
 await new Promise((resolve,reject)=>{const finish=error=>{clearTimeout(timer);worker.removeEventListener('statechange',changed);error?reject(error):resolve();};const changed=()=>{if(worker.state==='activated')finish();else if(worker.state==='redundant')finish(new Error('تعذّر تحديث خدمة الإشعارات'));};const timer=setTimeout(()=>finish(new Error('تأخر تشغيل خدمة الإشعارات؛ أعد المحاولة')),20000);worker.addEventListener('statechange',changed);changed();});
}
async function loadPushSdk(){return Promise.all([import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js'),import('https://www.gstatic.com/firebasejs/11.10.0/firebase-messaging.js')]);}
async function initializeWebPush(){
 if(!notificationUser||globalThis.Notification?.permission!=='granted')return false;
 if(pushInitializing)return pushInitializing;
 const epoch=notificationEpoch,userId=notificationUser;
 const pending=(async()=>{try{
  if(!('serviceWorker'in navigator))throw new Error('افتح الداشبورد بمتصفح يدعم إشعارات الخلفية مثل Chrome');
  pushState('جاري تفعيل إشعارات الخلفية…');
  const response=await fetch('./firebase-config.json',{cache:'no-store'});if(!response.ok)throw new Error('تعذّر تحميل إعدادات الإشعارات');const config=await response.json();
  if(!config.apiKey||!config.projectId||!config.messagingSenderId||!config.appId)throw new Error('إعدادات إشعارات الويب غير مكتملة');
  const [appApi,msgApi]=await loadPushSdk();if(!await msgApi.isSupported())throw new Error('هذا المتصفح لا يدعم إشعارات الخلفية؛ استخدم Chrome');
  const app=appApi.getApps().find(a=>a.name==='taktooka-dashboard')||appApi.initializeApp(config,'taktooka-dashboard');
  const messaging=msgApi.getMessaging(app),registration=await navigator.serviceWorker.register('./firebase-messaging-sw.js',{updateViaCache:'none'});
  await waitForPushWorker(registration);
  const token=await msgApi.getToken(messaging,{vapidKey:config.vapidKey||undefined,serviceWorkerRegistration:registration});
  if(!token)throw new Error('تعذّر تسجيل هذا الجهاز للإشعارات');if(epoch!==notificationEpoch)return false;
  const old=savedPush();if(old?.userId===userId&&old.token!==token)await noticeRpc('unregister',{token:old.token});
  await noticeRpc('register',{token,platform:'web'});
  if(epoch!==notificationEpoch){await noticeRpc('unregister',{token}).catch(()=>{});return false;}
  webMessageUnsubscribe?.();webRegistration=registration;webMessaging=messaging;webToken=token;rememberPush({userId,token});
  webMessageUnsubscribe=msgApi.onMessage(messaging,m=>{const d=m.data||{};if(d.recipient_id!==notificationUser)return;if(d.kind==='emergency')emergencyAlarm.notify(d.emergency_id);showDeviceNotice({id:d.notification_id,user_id:d.recipient_id,kind:d.kind,title:d.title||m.notification?.title,body:d.body||m.notification?.body,expires_at:d.expires_at,target:d}).catch(()=>{});refreshNotifications().catch(()=>{});});
  pushState('إشعارات الخلفية مفعّلة ✓');return true;
 }catch(e){if(epoch===notificationEpoch){webMessaging=null;pushState('إعادة تفعيل إشعارات الخلفية',message(e));}return false;}})();
 pushInitializing=pending;try{return await pending}finally{if(pushInitializing===pending)pushInitializing=null;}
}
async function noticeRpc(action,data={}){const r=await db.rpc('tkt_notification_action',{p_action:action,p_data:data});if(r.error)throw r.error;return r.data;}
async function refreshNotifications(){if(!notificationUser)return;const epoch=notificationEpoch,request=++noticeRequest,rows=await noticeRpc('list');if(epoch!==notificationEpoch||request!==noticeRequest)return;notificationRows=rows;if(noticesInitialized){for(const n of rows){if(observedNotices.has(n.id))continue;observedNotices.add(n.id);if(!n.read_at&&validNotice(n)){if(n.kind==='support'||n.kind==='recovery'){status(n.title+' · '+n.body);if(activePage==='support')loadSupport().catch(()=>{});}await showDeviceNotice(n);}}}else{rows.forEach(n=>observedNotices.add(n.id));noticesInitialized=true;}const count=notificationRows.filter(n=>!n.read_at&&n.kind!=='offer_end').length;$('notifications').textContent=`الإشعارات${count?' ('+count+')':''}`;const urgent=notificationRows.filter(n=>!n.read_at&&n.kind==='emergency').length;$('notifications').classList.toggle('emergency-notification',urgent>0);if(urgent)$('notifications').textContent='🔴 SOS طوارئ ('+urgent+') · '+$('notifications').textContent;}
async function startNotifications(){await stopNotifications();notificationUser=(await db.auth.getUser()).data.user?.id;if(!notificationUser)return;$('notifications').hidden=false;$('enableNotifications').hidden=false;if(canView('support'))await emergencyAlarm.start(notificationUser);if(canView('lines'))await lineAlarm.start(notificationUser);await refreshNotifications();
 notificationChannel=db.channel('admin-notifications-'+notificationUser).on('postgres_changes',{event:'INSERT',schema:'public',table:'tkt_notifications',filter:'user_id=eq.'+notificationUser},async payload=>{if(payload.new.kind==='emergency')emergencyAlarm.notify(payload.new.target?.emergency_id);if(!webMessaging)await showDeviceNotice(payload.new);await refreshNotifications();}).subscribe();
 notificationTimer=setInterval(()=>refreshNotifications().catch(()=>{}),15000);
 pushState('تفعيل إشعارات الجهاز');await initializeWebPush();
}
async function stopNotifications(unregister=false){emergencyAlarm.stop();lineAlarm.stop();notificationEpoch++;pushInitializing=null;clearInterval(notificationTimer);webMessageUnsubscribe?.();webMessageUnsubscribe=null;if(notificationChannel)await db.removeChannel(notificationChannel);notificationChannel=null;if(unregister&&notificationUser){const saved=savedPush(),token=webToken||(saved?.userId===notificationUser?saved.token:null);if(token)await noticeRpc('unregister',{token});rememberPush(null);if(webRegistration){const notices=await webRegistration.getNotifications();notices.forEach(n=>n.close());}}notificationUser=null;notificationRows=[];webToken=null;webMessaging=null;webRegistration=null;notified.clear();observedNotices.clear();noticesInitialized=false;$('notifications').hidden=true;$('enableNotifications').hidden=true;}
async function openNotification(n){await noticeRpc('read',{id:n.id});await refreshNotifications();const t=n.target||{};
 if(t.screen==='lines'){showPage('lines');await loadLines();await trackLine(t.line_id);}
 else if(t.screen==='emergency'){await openEmergency(t.emergency_id);}
 else if(t.screen==='ride'){showPage('rides');await loadRides();await trackRide(t.ride_id);}
 else if(t.screen==='support'){showPage('support');await loadSupport();await chat('support',supportRooms.find(r=>r.user_id===t.user_id)||{user_id:t.user_id,name:'محادثة دعم'});}
 else if(t.screen==='exchange_finance'){if(canView('exchanges')){showPage('exchanges');await exchangesPage.restore({id:t.agent_id});}}
 else if(t.screen==='exchange_support'){if(canView('support')){await loadSupport();const r=exchangeRooms.find(r=>r.id===t.agent_id);if(r)await openExchangeSupport(r);}}
 else if(t.screen==='recovery'){showPage('support');await loadSupport();const r=recovery.find(r=>r.id===t.thread_id);if(r)await chat('recovery',r);}
 else if(t.screen==='application'){showPage('applications');await loadApplications();const a=applications.find(a=>a.user_id===t.user_id);if(a)await applicationDetail(a);else { $('applicationStatus').value='';$('applicationSearch').value=t.user_id;const rows=await applicationRpc('list',{limit:200});const found=rows.find(a=>a.user_id===t.user_id);if(found)await applicationDetail(found); }}
 else if(t.screen==='finance'||t.screen==='wallet'){showPage('finance');await loadFinance();}
 else {showPage('users');await loadUsers();}
}
async function showNotificationInbox(){await refreshNotifications();const body=openDetail('الإشعارات',{name:'notifications',args:[]});body.append(button('قراءة الكل',async()=>{await noticeRpc('read_all');await refreshNotifications();closeDetail();}));for(const n of notificationRows.filter(n=>n.kind!=='offer_end'))body.append(record((n.read_at?'':'● ')+n.title,n.body+' · '+dates(n.created_at),[button('فتح',()=>openNotification(n))]));empty(body);}
$('notifications').onclick=()=>run(showNotificationInbox);
$('enableNotifications').onclick=()=>run(async()=>{if(!('Notification'in window))throw new Error('هذا المتصفح لا يدعم إشعارات الجهاز');const permission=await Notification.requestPermission();if(permission!=='granted')throw new Error('اسمح بالإشعارات من إعدادات المتصفح');if(await initializeWebPush())status('تم تفعيل إشعارات الجهاز والخلفية');else status($('enableNotifications').title||'تعذّر تفعيل إشعارات الخلفية');});
window.addEventListener('online',()=>{if(notificationUser)initializeWebPush().catch(()=>{});});
if('serviceWorker'in window.navigator)window.navigator.serviceWorker.addEventListener('message',event=>{if(event.data?.type==='tkt-notice-click'&&notificationUser)run(async()=>{await refreshNotifications();const n=notificationRows.find(n=>n.id===event.data.id);if(n)await openNotification(n);});});
let dashboardAccess=null,inventorySummary={},inventoryCategory='rides_completed',inventoryItems=[],inventoryHasMore=false,inventoryTimer,staffRows=[],editingStaff=null;
const permissionPages=[['lines','الخطوط'],['inventory','الجرد والحسابات'],['overview','نظرة عامة والتتبع'],['rides','الرحلات'],['applications','تسجيل المركبات'],['users','المستخدمون والكباتن'],['finance','المحافظ والأكواد والشركة والأداء'],['support','الدعم والاسترجاع'],['pricing','التسعيرة'],['coverage','التغطية والتوزيع'],['wheel','عجلة الجوائز'],['banners','البنرات'],['favorites','العناوين المفضلة'],['security','الدخول والأمان'],['audit','سجل الإدارة والأرشيف']];
const inventorySpecs=[
 ['rides_completed','عدد الرحلات المكتملة','✓','green','كل الرحلات التي اكتملت، بما فيها المؤرشفة.'],
 ['rides_cancelled','عدد الرحلات الملغية','×','red','كل الرحلات التي أُلغيَت.'],
 ['rides_running','عدد الرحلات الجارية','↗','blue','تشمل قيد البحث، والكابتن بالطريق، ووصل الكابتن، والرحلة جارية.'],
 ['vehicles_pending','عدد المركبات قيد التسجيل','⌛','amber','طلبات تسجيل المركبات التي أُرسلت وتنتظر المراجعة.'],
 ['vehicles_registered','عدد المركبات المسجلة','▣','green','حسابات الكباتن وطلبات المركبات المعتمدة.'],
 ['vehicles_incomplete','عدد المركبات لديها نقص بيانات','!','amber','طلبات التسجيل التي أُعيدت للكابتن لغرض تعديل البيانات أو المستمسكات.'],
 ['vehicles_never','عدد المركبات غير المشتركة','○','red','المركبات المسجلة التي لم يُحدد لها اشتراك بعد.'],
 ['vehicles_active','عدد المركبات المشتركة','✓','green','المركبات التي ما زال اشتراكها ساريًا الآن.'],
 ['vehicles_expired','عدد المركبات المنتهي اشتراكها','◷','amber','المركبات التي لديها تاريخ اشتراك سابق وانتهى.'],
 ['vehicle_funds','أموال المركبات المخزونة في الشركة','د.ع','blue','مجموع مستحقات الكباتن الموجبة المحفوظة بالمحافظ؛ افتح الكارت لمعرفة رصيد كل كابتن.'],
 ['customers','عدد الزبائن','◉','blue','حسابات الزبائن، باستثناء حسابات الإدارة والموظفين والمركبات المسجلة.'],
 ['customer_funds','أموال الزبائن المخزونة في الشركة','د.ع','green','مجموع أرصدة محافظ الزبائن الموجبة؛ افتح الكارت لمعرفة رصيد كل زبون.']
];
function canView(page){if(page==='exchanges'||page==='server')return dashboardAccess?.owner===true;if(page==='company'||page==='rewards'||page==='commerce')page='finance';if(page==='restaurant-support')page='support';return !dashboardAccess||dashboardAccess.owner||page!=='staff'&&dashboardAccess.permissions?.[page]?.view===true;}
function canEdit(page){if(page==='exchanges'||page==='server')return dashboardAccess?.owner===true;if(page==='company'||page==='rewards'||page==='commerce')page='finance';if(page==='restaurant-support')page='support';return !dashboardAccess||dashboardAccess.owner||page!=='staff'&&dashboardAccess.permissions?.[page]?.view===true&&dashboardAccess.permissions?.[page]?.edit===true;}
async function dashboardRpc(name,action,data={}){const r=await db.rpc(name,{p_action:action,p_data:data});if(r.error)throw r.error;return r.data;}
const accountAdmin=createAccountAdmin({document,rpc:(action,data)=>dashboardRpc('tkt_account_admin',action,data),invoke:async body=>{const {data,error}=await db.functions.invoke('taktooka-owner-account-delete',{body});if(error||!data?.ok){let detail=data?.error;try{if(!detail&&error?.context)detail=(await error.context.json()).error;}catch{}throw new Error(detail||'تعذّر حذف الحساب؛ أعد المحاولة.');}return data;},openDetail,button,text,record,money,localPhone,run,notify:status,canManage:()=>dashboardAccess?.owner===true,onDeleted:async result=>{closeDetail();renderCache.clear?.();if(result.self){await db.auth.signOut();location.reload();return;}await loadPage(activePage);}});
const exchangesPage=createExchangesPage({document,rpc:(action,data)=>dashboardRpc('tkt_exchange',action,data),run,notify:status,money,dates,openDetail,closeDetail,openProfile:id=>openUserProfile(id),resetPassword:u=>resetPassword(u),openSupport:openExchangeSupport,openStatement:id=>operations.statement(id),deleteAccount:(kind,id)=>accountAdmin.open(kind,id)});
const serverMonitor=createServerMonitor({document,rpc:(action,data)=>dashboardRpc('tkt_server_monitor',action,data),run});
const commercePage=createCommercePage({document,rpc:async(action,data={})=>{const {data:result,error}=await db.rpc('tkt_commerce',{p_action:action,p_data:data});if(error)throw error;return result;},money,canEdit,run,profile:openUserProfile,phone:localPhone});
const companyPage=createCompanyPage({document,rpc:(action,data)=>dashboardRpc('tkt_company',action,data),money,dates,canEdit:()=>canEdit('finance'),canOpenProfile:()=>canView('inventory')||canView('users'),openProfile:id=>run(()=>openUserProfile(id)),confirmVoid:()=>prompt('سبب إلغاء المصروف')});
async function refreshDashboardAccess(){const r=await db.rpc('tkt_dashboard_access');if(r.error)throw r.error;dashboardAccess=r.data;applyDashboardPermissions();}
const couponCardPrinter=createCouponCardPrinter({document,rpc:(action,data)=>dashboardRpc('tkt_coupon_cards',action,data),canEdit:()=>canEdit('finance'),run,notify:status,dates});
const couponRewards=createCouponRewards({document,onModeChange:couponCardPrinter.mode,onGenerateCards:couponCardPrinter.generate,onLoadCards:couponCardPrinter.load,rpc:(action,data)=>dashboardRpc('tkt_coupon_rewards',action,data),money,dates,canEdit:()=>canEdit('finance'),notify:status,run,openDetail,openProfile:id=>canView('inventory')||canView('users')?openUserProfile(id):Promise.resolve()});
function applyDashboardPermissions(){
 companyPage.syncPermissions();couponRewards.syncPermissions();
 document.querySelectorAll('[data-page]').forEach(el=>el.hidden=!canView(el.dataset.page));
 const restrictions={pricing:['savePricing','addTier'],coverage:['draw','undo','finish','save'],wheel:['saveWheelState'],banners:['bannerForm']};
 for(const [page,ids]of Object.entries(restrictions))for(const id of ids){const el=$(id);if(!el)continue;if(el.tagName==='FORM')el.querySelectorAll('input,select,button').forEach(x=>x.disabled=!canEdit(page));else el.disabled=!canEdit(page);}
 document.querySelectorAll('#tiers button').forEach(el=>el.disabled=!canEdit('pricing'));for(const page of ['pricing','coverage'])document.querySelectorAll(`#page-${page} input`).forEach(el=>el.disabled=!canEdit(page)&&el.id!=='previewDistance');
}
async function loadInventory(){await Promise.all([refreshInventorySummary(),$('inventoryDetails').closest('dialog[open]')?loadInventoryRows():Promise.resolve()]);}
async function refreshInventorySummary(){const result=await dashboardRpc('tkt_inventory','summary');inventorySummary=result;renderInventoryCards();$('inventoryUpdated').textContent='آخر تحديث: '+dates(result.server_now);}
function renderInventoryCards(){if(!renderCache.changed('inventory',[inventorySummary,inventoryCategory]))return;const cards=$('inventoryCards');cards.replaceChildren();for(const [key,label,icon,tone]of inventorySpecs){const tile=button('',async()=>{inventoryCategory=key;$('inventorySearch').value='';renderInventoryCards();await loadInventoryRows();openSectionScreen($('inventoryDetails'),$('inventoryListTitle').textContent);},'inventory-tile');tile.dataset.tone=tone;tile.dataset.category=key;tile.classList.toggle('selected',key===inventoryCategory);tile.setAttribute('aria-pressed',String(key===inventoryCategory));const value=text('strong',key.endsWith('_funds')?money(inventorySummary[key]||0):new Intl.NumberFormat('en-US').format(inventorySummary[key]||0));value.className='inventory-value'+(key.endsWith('_funds')?' money-value':'');tile.append(Object.assign(text('span',icon),{className:'inventory-icon'}),Object.assign(text('span',label),{className:'inventory-label'}),value,Object.assign(text('span','عرض التفاصيل ←'),{className:'inventory-open'}));cards.append(tile);}}
async function loadInventoryRows(more=false){const category=inventoryCategory,search=$('inventorySearch').value.trim();const result=await dashboardRpc('tkt_inventory','rows',{category,search,limit:30,offset:more?inventoryItems.length:0});if(category!==inventoryCategory||search!==$('inventorySearch').value.trim())return;inventoryItems=more?[...inventoryItems,...result.rows]:result.rows;inventoryHasMore=result.has_more;const spec=inventorySpecs.find(x=>x[0]===category);$('inventoryListTitle').textContent=spec[1];$('inventoryDescription').textContent=spec[4];$('inventoryCount').textContent=new Intl.NumberFormat('en-US').format(result.total)+' سجل';$('moreInventory').hidden=!inventoryHasMore;renderInventoryRows();}
function renderInventoryRows(){const list=$('inventoryRows');list.replaceChildren();for(const item of inventoryItems){
 if(inventoryCategory.startsWith('rides_')){const actions=[];if(item.rider_id)actions.push(button('عرض ملف الزبون',()=>openUserProfile(item.rider_id)));if(item.captain_id)actions.push(button('عرض ملف الكابتن',()=>openUserProfile(item.captain_id)));if(canView('rides'))actions.push(button('تفاصيل الرحلة',()=>trackRide(item.id)));list.append(record(`${item.pickup_name||'الانطلاق'} ← ${item.destination_name||'الوصول'}`,[['مرجع الرحلة',item.id],['الحالة',stateNames[item.status]||item.status],...tripFacts(item),['الكروة',money(item.fare||0)],['الزبون',`${item.rider_name||'—'} · ${localPhone(item.rider_phone)}`],['الكابتن',`${item.captain_name||'لم يُحدد'} · ${localPhone(item.captain_phone)}`],['تاريخ الرحلة',dates(item.created_at)]],actions));}
 else{const entries=[['الهاتف',localPhone(item.phone)],['نوع الحساب',item.vehicle?'مركبة / كابتن':'زبون'],['الرصيد في الشركة',money(item.balance)],['حالة الحساب',item.archived?'مؤرشف':item.blocked?'محظور':'فعال']];if(item.vehicle)entries.push(['الاشتراك',{never:'غير مشترك',active:'مشترك',expired:'منتهي'}[item.subscription_state]],['نهاية الاشتراك',dates(item.expires_at)]);if(item.application_status)entries.push(['طلب المركبة',applicationNames[item.application_status]||item.application_status]);if(item.chassis)entries.push(['رقم الشاصي',item.chassis]);if(item.reason&&item.application_status==='changes_required')entries.push(['البيانات المطلوبة',item.reason]);list.append(record(item.full_name||item.name||'بدون اسم',entries,[button('عرض الملف الشخصي',()=>openUserProfile(item.user_id))]));}
 }empty(list);}
async function openUserProfile(userId){const result=await dashboardRpc('tkt_inventory','profile',{user_id:userId}),p=result.profile;const body=openDetail('الملف الشخصي'),epoch=dialogEpoch;const heading=text('div','');heading.className='profile-heading';const avatar=text('div',(p.full_name||p.name||'؟').slice(0,1));avatar.className='profile-avatar profile-initial';heading.append(avatar,text('h2',p.full_name||p.name||'بدون اسم'));body.append(heading);if(p.avatar_path){try{const r=await db.storage.from('profile-photos').createSignedUrl(p.avatar_path,300);if(r.data?.signedUrl){const img=document.createElement('img');img.className='profile-avatar';img.src=r.data.signedUrl;img.alt='الصورة الشخصية';avatar.replaceWith(img);}}catch(_){}}
 if(epoch!==dialogEpoch)return;
 const summary=text('div','');summary.className='profile-summary';for(const [label,value]of [['الرحلات المكتملة',result.rides.completed],['الرحلات الملغية',result.rides.cancelled],['الرحلات الجارية',result.rides.running]]){const tile=text('div',label);tile.prepend(text('strong',new Intl.NumberFormat('en-US').format(value)));summary.append(tile);}body.append(summary);
 const identity=text('section','');identity.className='profile-section';identity.append(text('h3','بيانات الحساب'),facts([['الاسم',p.name],['رقم الهاتف',localPhone(p.phone)],['نوع الحساب',p.vehicle?'كابتن / مركبة':'زبون'],['الحالة',p.archived?'مؤرشف':p.blocked?'محظور':'فعال'],['تاريخ التسجيل',dates(p.created_at)],['معرّف الحساب',p.user_id]]));const contact=text('div','');contact.className='controls';for(const [label,url]of [['اتصال','tel:'+p.phone],['واتساب',whatsappUrl(p.phone) ]]){if(!url)continue;const a=text('a',label);a.href=url;a.target='_blank';a.rel='noopener';a.className='profile-contact';contact.append(a);}identity.append(contact);body.append(identity);
 if(p.vehicle||p.application_status){const vehicle=text('section','');vehicle.className='profile-section';vehicle.append(text('h3','المركبة والاشتراك'),facts([['الاسم الثلاثي',p.full_name],['رقم الشاصي',p.chassis],['اللون',p.color],['الموديل',p.model],['المحافظة',p.province],['المنطقة',p.area],['حالة تسجيل المركبة',applicationNames[p.application_status]||p.application_status||'—'],['الاشتراك',{never:'غير مشترك',active:'فعال',expired:'منتهي'}[p.subscription_state]],['نهاية الاشتراك',dates(p.expires_at)],['المطلوب تعديله',p.reason]]));body.append(vehicle);}
 if(canView('inventory')||canView('finance')){const wallet=text('section','');wallet.className='profile-section';wallet.append(text('h3',p.vehicle?'مستحقات الكابتن':'محفظة الزبون'),text('strong',money(p.balance||0)));if(canView('finance'))wallet.append(button('عرض كشف الحساب',()=>ledger(p)));if(result.payments?.length){wallet.append(text('h3','آخر مدفوعات الاشتراك'));for(const payment of result.payments)wallet.append(text('p',`${money(payment.amount)} · ${dates(payment.created_at)} · حتى ${dates(payment.expires_at)}`));}body.append(wallet);}
 if(canView('lines')){if(p.captain||p.vehicle){const section=text('section','');section.id='profileLineReport';section.className='profile-section';body.append(section);profileLineRefreshAt=0;await refreshProfileLines(userId,epoch);}else{const lines=await linesRpc('list');if(epoch!==dialogEpoch)return;const related=lines.filter(l=>l.customer_id===userId);if(related.length){body.append(text('h3','خطوط الزبون'));for(const l of related)body.append(record(lineKindNames[l.kind],lineFacts(l),[button('تفاصيل الخط والتتبع',()=>trackLine(l.id))]));}}}

 if(p.vehicle||p.application_status)startCaptainProfile(userId,body,epoch);
}
function stopCaptainProfile(){
 if(profileLiveChannel){db.removeChannel(profileLiveChannel);profileLiveChannel=null;}
 if(profileMotionFrame)cancelAnimationFrame(profileMotionFrame);
 clearInterval(profileStatusTimer);profileStatusTimer=null;profileMarker=null;profileLiveData=null;profileCentered=false;profilePositionTime=-Infinity;
}
async function captainProfileRpc(userId,documents=false){
 const result=await dashboardRpc('tkt_inventory','profile',{user_id:userId}),p=result.profile;
 const allowed=Boolean(dashboardAccess?.owner||dashboardAccess?.permissions?.applications?.view);
 let images={};
 if(documents&&allowed){const {data,error}=await db.from('tkt_captain_applications').select('documents').eq('user_id',userId).maybeSingle();if(error)throw error;for(const key of ['id_front','id_back'])if(data?.documents?.[key])images[key]=data.documents[key];}
 return {captain:{user_id:p.user_id,name:p.name,captain:p.captain,online:p.online,lat:p.lat,lng:p.lng,location_at:p.location_at},documents:images,documents_allowed:allowed,server_now:new Date().toISOString()};
}
function captainProfileStatus(){
 const el=$('captainProfileStatus'),p=profileLiveData;if(!el||!p)return;
 const timestamp=Date.parse(p.location_at),age=Number.isFinite(timestamp)?Math.max(0,Math.floor((Date.now()+profileServerOffset-timestamp)/1000)):null;
 const hasPoint=Number.isFinite(p.lat)&&Number.isFinite(p.lng)&&Number.isFinite(timestamp);
 const live=hasPoint&&p.online&&age<=15;
 el.className='captain-location-status'+(live?' live':' stale');
 el.textContent=!hasPoint?'لم يصل موقع الكابتن بعد':!p.online?'الكابتن غير متصل · آخر موقع قبل '+age+' ثانية':live?'● موقع مباشر · آخر تحديث قبل '+age+' ثانية':'الموقع متأخر · آخر تحديث قبل '+age+' ثانية';
 $('captainProfileLocationTime').textContent='وقت الموقع: '+dates(p.location_at);
}
function moveCaptainProfileMarker(point,epoch){
 if(profileMotionFrame)cancelAnimationFrame(profileMotionFrame);
 const from=profileMarker.getLatLng(),started=performance.now();
 const frame=()=>{if(epoch!==dialogEpoch||!profileMarker)return;const progress=Math.min(1,(performance.now()-started)/700);profileMarker.setLatLng([from.lat+(point[0]-from.lat)*progress,from.lng+(point[1]-from.lng)*progress]);if(progress<1)profileMotionFrame=requestAnimationFrame(frame);else profileMotionFrame=null;};
 profileMotionFrame=requestAnimationFrame(frame);
}
function applyCaptainProfileLocation(result,epoch){
 if(epoch!==dialogEpoch||dialogMode!=='profile')return;
 const p=result.captain;if(!p)return;
 const received=Date.parse(p.location_at);
 if(Number.isFinite(received)&&received<profilePositionTime)return;
 profileLiveData=p;profileServerOffset=Date.parse(result.server_now)-Date.now();captainProfileStatus();
 if(!Number.isFinite(p.lat)||!Number.isFinite(p.lng)||!Number.isFinite(received))return;
 const point=[p.lat,p.lng],changed=received>profilePositionTime;
 if(!profileMarker){profileMarker=L.marker(point,{icon:L.divIcon({className:'',html:'<div class="captain-profile-marker">🛺</div>',iconSize:[40,40],iconAnchor:[20,20]})}).addTo(dialogMap);profileMarker.bindPopup(text('span',p.name||'الكابتن'));}
 else if(changed)moveCaptainProfileMarker(point,epoch);
 profilePositionTime=received;
 if(!profileCentered){dialogMap.setView(point,17);profileCentered=true;}
 else if(profileFollow&&changed)dialogMap.panTo(point,{animate:true,duration:0.7});
}
async function updateCaptainProfile(){
 if(dialogRefreshing||dialogMode!=='profile'||!dialogMap)return;
 dialogRefreshing=true;const epoch=dialogEpoch,userId=dialogKey;
 try{const result=await captainProfileRpc(userId);applyCaptainProfileLocation(result,epoch);if(canView('lines')&&$('profileLineReport')&&Date.now()-profileLineRefreshAt>10000){profileLineRefreshAt=Date.now();try{await refreshProfileLines(userId,epoch);}catch(e){if(epoch===dialogEpoch)status('تعذر تحديث بيانات الخطوط؛ موقع الكابتن مستمر بالتحديث');}}}
 catch(e){if(epoch===dialogEpoch&&$('captainProfileStatus')){$('captainProfileStatus').className='captain-location-status stale';$('captainProfileStatus').textContent='تعذر تحديث الموقع؛ آخر تحديث: '+dates(profileLiveData?.location_at);}}
 finally{dialogRefreshing=false;}
}
async function loadCaptainIdentity(userId,gallery,epoch){
 gallery.replaceChildren(text('p','جاري تحميل صور الجنسية…'));
 try{
  const result=await captainProfileRpc(userId,true);if(epoch!==dialogEpoch)return;
  applyCaptainProfileLocation(result,epoch);gallery.replaceChildren();
  if(!result.documents_allowed){gallery.append(text('p','عرض صور الجنسية يحتاج صلاحية تسجيل المركبات'));return;}
  await Promise.all([['id_front','وجه الجنسية'],['id_back','خلف الجنسية']].map(async([slot,label])=>{
   const card=text('figure','');card.append(text('figcaption',label));gallery.append(card);const path=result.documents?.[slot];
   if(!path){card.append(text('p','لم تُرفع هذه الصورة'));return;}
   try{const {data,error}=await db.storage.from('captain-documents').createSignedUrl(path,600);if(epoch!==dialogEpoch)return;
    if(error||!data?.signedUrl)throw error||new Error('DOCUMENT_UNAVAILABLE');
    const link=text('a','');link.href=data.signedUrl;link.target='_blank';link.rel='noopener noreferrer';link.setAttribute('aria-label','تكبير '+label);
    const img=document.createElement('img');img.src=data.signedUrl;img.alt=label;img.referrerPolicy='no-referrer';img.loading='lazy';img.onerror=()=>{if(epoch===dialogEpoch){link.replaceWith(text('p','تعذر تحميل الصورة؛ اضغط تحديث الصور'));}};link.append(img);card.append(link,text('small','اضغط الصورة للتكبير'));
   }catch(_){if(epoch===dialogEpoch)card.append(text('p','تعذر عرض الصورة؛ اضغط تحديث الصور'));}
  }));
 }catch(_){if(epoch===dialogEpoch)gallery.replaceChildren(text('p','تعذر تحميل المستمسكات؛ اضغط تحديث الصور'));}
}
function startCaptainProfile(userId,body,epoch){
 dialogMode='profile';dialogKey=userId;profileFollow=true;
 const section=text('section','');section.className='profile-section captain-live-section';section.append(text('h3','موقع الكابتن مباشر'));
 const controls=text('div','');controls.className='controls';const follow=text('label',''),checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.checked=true;checkbox.onchange=()=>{profileFollow=checkbox.checked;if(profileFollow&&profileMarker)dialogMap.panTo(profileMarker.getLatLng());};follow.append(checkbox,text('span','متابعة الكابتن على الخريطة'));controls.append(follow,button('تحديث الموقع',updateCaptainProfile));section.append(controls);
 section.append(Object.assign(text('p','بانتظار موقع الكابتن…'),{id:'captainProfileStatus',className:'captain-location-status stale'}),Object.assign(text('p',''),{id:'captainProfileLocationTime'}),Object.assign(text('div',''),{id:'captainProfileMap',className:'admin-map captain-profile-map'}));body.append(section);
 dialogMap=mapFor('captainProfileMap');dialogMap.on('dragstart',()=>{profileFollow=false;checkbox.checked=false;});setTimeout(()=>{if(epoch===dialogEpoch)dialogMap?.invalidateSize();},0);
 profileLiveChannel=db.channel('captain-profile-'+userId+'-'+epoch).on('postgres_changes',{event:'UPDATE',schema:'public',table:'tkt_profiles',filter:'user_id=eq.'+userId},()=>{if(epoch===dialogEpoch)scheduleLiveRefresh();}).subscribe();
 profileStatusTimer=setInterval(captainProfileStatus,1000);
 const docs=text('section','');docs.className='profile-section';const gallery=text('div','');gallery.className='application-documents captain-identity-gallery';docs.append(text('h3','صور الجنسية'),button('تحديث الصور',()=>loadCaptainIdentity(userId,gallery,epoch)),gallery);body.append(docs);
 unawaitedCaptainProfile(updateCaptainProfile());unawaitedCaptainProfile(loadCaptainIdentity(userId,gallery,epoch));
}
function unawaitedCaptainProfile(promise){promise.catch(()=>{});}

function permissionEditor(value={}){const table=text('table','');table.className='permission-table';const head=text('thead',''),tr=text('tr','');['القسم','عرض','تعديل'].forEach(label=>tr.append(text('th',label)));head.append(tr);table.append(head);const tbody=text('tbody','');for(const [key,label]of permissionPages){const row=text('tr','');row.append(text('td',label));const inputs={};for(const kind of ['view','edit']){const td=text('td',''),input=document.createElement('input');input.type='checkbox';input.dataset.permission=key;input.dataset.access=kind;input.checked=value[key]?.[kind]===true;input.setAttribute('aria-label',`${kind==='view'?'عرض':'تعديل'} ${label}`);if(key==='inventory'&&kind==='edit'){input.disabled=true;input.checked=false;}inputs[kind]=input;td.append(input);row.append(td);}inputs.view.onchange=()=>{if(!inputs.view.checked)inputs.edit.checked=false;};inputs.edit.onchange=()=>{if(inputs.edit.checked)inputs.view.checked=true;};tbody.append(row);}table.append(tbody);$('staffPermissions').replaceChildren(table);}
function selectedStaffPermissions(){const result={};for(const [key]of permissionPages){const view=document.querySelector(`[data-permission="${key}"][data-access="view"]`).checked,edit=document.querySelector(`[data-permission="${key}"][data-access="edit"]`).checked;if(view)result[key]={view,edit};}if(!Object.keys(result).length)throw new Error('حدد للموظف صلاحية عرض قسم واحد على الأقل');return result;}
function clearStaffForm(){editingStaff=null;$('staffForm').reset();$('staffPhone').disabled=false;$('staffPasswordLabel').hidden=false;$('staffPassword').required=true;$('staffFormTitle').textContent='إضافة موظف جديد';$('saveStaff').textContent='إنشاء حساب الموظف';$('staffFormStatus').textContent='';permissionEditor();}
async function loadStaff(){staffRows=await dashboardRpc('tkt_staff','list');renderStaff();await accountAdmin.load();if(!$('staffPermissions').childElementCount)permissionEditor();}
function renderStaff(){const list=$('staffList');list.replaceChildren();$('staffMetrics').replaceChildren();for(const [label,value]of [['كل الموظفين',staffRows.length],['الموظفون الفعالون',staffRows.filter(s=>s.active).length],['الحسابات المتوقفة',staffRows.filter(s=>!s.active).length]]){const tile=text('div',label);tile.className='metric';tile.prepend(text('strong',new Intl.NumberFormat('en-US').format(value)));$('staffMetrics').append(tile);}const q=$('staffSearch').value.trim();for(const s of staffRows.filter(s=>!q||`${s.name} ${localPhone(s.phone)}`.includes(q))){const item=record(s.name,[['رقم الدخول',localPhone(s.phone)],['الحساب',s.active?'فعال':'متوقف'],['تاريخ الإنشاء',dates(s.created_at)]],[button('حذف الحساب',()=>accountAdmin.open('user',s.user_id),'danger'),button('تعديل الصلاحيات',async()=>editStaff(s)),button(s.active?'إيقاف الحساب':'تفعيل الحساب',async()=>{await dashboardRpc('tkt_staff','update',{...s,active:!s.active});await loadStaff();status('تم تحديث حالة حساب الموظف');},s.active?'danger':'secondary'),button('تغيير كلمة السر',async()=>resetStaffPassword(s))]);const chips=text('div','');chips.className='staff-permission-chips';for(const [key,label]of permissionPages)if(s.permissions[key]?.view)chips.append(text('span',label+(s.permissions[key].edit?' · عرض وتعديل':' · عرض')));item.firstChild.append(chips);list.append(item);}empty(list);}
function editStaff(s){editingStaff=s;$('staffName').value=s.name;$('staffPhone').value=localPhone(s.phone);$('staffPhone').disabled=true;$('staffPassword').value='';$('staffPassword').required=false;$('staffPasswordLabel').hidden=true;$('staffActive').checked=s.active;$('staffFormTitle').textContent='تعديل حساب '+s.name;$('saveStaff').textContent='حفظ الصلاحيات';$('staffFormStatus').textContent='';permissionEditor(s.permissions);openSectionScreen($('staffEditor'),$('staffFormTitle').textContent);}
async function invokeStaff(body){const {data,error}=await db.functions.invoke('taktooka-staff-admin',{body});if(error||!data?.ok){let detail=data?.error;try{if(!detail&&error?.context)detail=(await error.context.json()).error;}catch(_){}throw new Error(detail||error?.message||'تعذّر تحديث حساب الموظف');}return data;}
function resetStaffPassword(s){const body=openDetail('تغيير كلمة سر الموظف'),password=inputField('كلمة السر الجديدة','','password');password.input.minLength=8;password.input.maxLength=128;password.input.autocomplete='new-password';body.append(text('p',s.name+' · '+localPhone(s.phone)),password.box,button('حفظ كلمة السر',async()=>{if(password.input.value.length<8)throw new Error('كلمة السر 8 أحرف أو أرقام على الأقل');await invokeStaff({op:'reset_password',user_id:s.user_id,password:password.input.value});password.input.value='';closeDetail();status('تم تغيير كلمة سر الموظف');}));}
$('staffForm').onsubmit=e=>{e.preventDefault();run(async()=>{const permissions=selectedStaffPermissions(),name=$('staffName').value.trim();if(!name)throw new Error('اكتب اسم الموظف');if(editingStaff){await dashboardRpc('tkt_staff','update',{user_id:editingStaff.user_id,name,permissions,active:$('staffActive').checked});clearStaffForm();await loadStaff();$('staffFormStatus').textContent='تم حفظ صلاحيات الموظف؛ تسري مباشرة.';}else{const phone=localPhone($('staffPhone').value),password=$('staffPassword').value;if(!/^07\d{9}$/.test(phone))throw new Error('رقم الهاتف يبدأ 07 ويتكون من 11 رقم');if(password.length<8)throw new Error('كلمة السر 8 أحرف أو أرقام على الأقل');await invokeStaff({op:'create',name,phone,password,permissions,active:$('staffActive').checked});clearStaffForm();await loadStaff();$('staffFormStatus').textContent=`تم إنشاء حساب ${name}. رقم الدخول: ${phone}. أعطِ الموظف كلمة السر التي حددتها.`;}});};
$('clearStaff').onclick=clearStaffForm;$('refreshStaff').onclick=()=>run(loadStaff);$('staffSearch').oninput=renderStaff;
$('refreshInventory').onclick=()=>run(loadInventory);$('moreInventory').onclick=()=>run(()=>loadInventoryRows(true));$('inventorySearchForm').onsubmit=e=>{e.preventDefault();run(()=>loadInventoryRows());};
function startInventoryRefresh(){clearInterval(inventoryTimer);inventoryTimer=setInterval(()=>{if(!document.hidden&&!busy){if(activePage==='company')companyPage.load({summaryOnly:true});}},15000);}

const EmergencyAudioContext=globalThis.AudioContext||globalThis.webkitAudioContext;
const emergencyAlarm=createEmergencyAlarm({
 fetchCases:()=>emergencyRpc('list'),
 createAudioContext:EmergencyAudioContext?()=>new EmergencyAudioContext():null,
 onState:state=>{const control=$('enableEmergencySound');control.hidden=!state.active;control.disabled=!state.supported;control.classList.toggle('emergency-notification',state.openCount>0);control.textContent=!state.supported?'المتصفح لا يدعم صوت الطوارئ':(state.enabled?'صوت الطوارئ مفعّل':'تفعيل صوت الطوارئ')+(state.openCount?' · '+state.openCount+' حالة مفتوحة':'');control.title=state.error||'يستمر الصوت حتى التعامل مع كل الحالات المفتوحة';}
});
$('enableEmergencySound').onclick=()=>emergencyAlarm.arm();
const unlockEmergencySound=event=>{if(event.isTrusted)emergencyAlarm.arm();};
document.addEventListener('pointerdown',unlockEmergencySound,{capture:true});
document.addEventListener('keydown',unlockEmergencySound,{capture:true});
document.addEventListener('visibilitychange',()=>{if(!document.hidden)emergencyAlarm.refresh();});



// Promotional images are public; row/storage mutation permissions are admin-only.
let bannerRows=[], bannerUploads=false;
const bannerBucket=db.storage.from('taktooka-banners');
async function loadBanners(){
 const {data,error}=await db.from('tkt_home_banners').select('*').order('sort_order').order('created_at').order('id').limit(100);
 if(error)throw error;bannerRows=data;renderBanners();
}
function renderBanners(){
 for(const slot of [1,2]){
  const list=$('bannerList'+slot);list.replaceChildren();
  for(const row of bannerRows.filter(x=>x.slot===slot)){
   const card=text('article','');card.className='banner-item';
   const image=document.createElement('img');image.src=bannerBucket.getPublicUrl(row.image_path).data.publicUrl;image.alt=row.title||'صورة البنر';image.loading='lazy';
   card.append(image,text('strong',row.title||'بدون عنوان'),text('small',`الترتيب: ${row.sort_order} · ${row.enabled?'فعّالة':'متوقفة'} · ${dates(row.created_at)}`));
   const controls=text('div','');controls.className='banner-controls';
   controls.append(button('تعديل',()=>editBanner(row)),button(row.enabled?'إيقاف':'تفعيل',async()=>{await saveBanner(row.id,{enabled:!row.enabled});await loadBanners()}),button('حذف',async()=>{
    if(!confirm('حذف هذه الصورة من البنر نهائياً؟'))return;
    const {error}=await db.from('tkt_home_banners').delete().eq('id',row.id).select('id').single();if(error)throw error;
    const removed=await bannerBucket.remove([row.image_path]);await loadBanners();status(removed.error?'حُذفت من التطبيق، لكن تعذّر تنظيف ملف الصورة من التخزين.':'تم حذف صورة البنر');
   },'danger'));
   card.append(controls);list.append(card);
  }empty(list);
 }
}
async function saveBanner(id,fields){const {error}=await db.from('tkt_home_banners').update(fields).eq('id',id).select('id').single();if(error)throw error;}
function editBanner(row){
 const body=openDetail('تعديل صورة البنر'),title=inputField('عنوان الصورة',row.title),order=inputField('الترتيب — الرقم الأصغر أولاً',row.sort_order,'number');title.input.maxLength=120;order.input.min=0;order.input.max=10000;
 const label=text('label','مكان الصورة'),slot=document.createElement('select');for(const [value,name]of [[1,'بنر 1 — فوك'],[2,'بنر 2 — جوه']]){const option=text('option',name);option.value=value;slot.append(option)}slot.value=row.slot;label.append(slot);
 body.append(title.box,label,order.box,button('حفظ التعديل',async()=>{const n=Number(order.input.value);if(!Number.isInteger(n)||n<0||n>10000)throw new Error('الترتيب رقم من 0 إلى 10000');await saveBanner(row.id,{title:title.input.value.trim(),slot:Number(slot.value),sort_order:n});closeDetail();await loadBanners();status('تم حفظ صورة البنر')}));
}
async function bannerJpeg(file){
 if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>5242880)throw new Error('اختَر JPG أو PNG أو WebP بحجم لا يتجاوز 5 ميغابايت');
 const url=URL.createObjectURL(file);
 try{
  const image=new Image();image.src=url;await image.decode();if(!image.width||!image.height)throw new Error('الصورة غير صالحة');
  const scale=Math.min(1,1600/image.width,1600/image.height),canvas=document.createElement('canvas');canvas.width=Math.round(image.width*scale);canvas.height=Math.round(image.height*scale);
  const ctx=canvas.getContext('2d');ctx.fillStyle='#ffffff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(image,0,0,canvas.width,canvas.height);
  return await new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error('تعذّر ضغط الصورة')),'image/jpeg',.88));
 }finally{URL.revokeObjectURL(url)}
}
let bannerPreviewUrls=[];
function clearBannerPreviews(){bannerPreviewUrls.forEach(url=>URL.revokeObjectURL(url));bannerPreviewUrls=[];$('bannerPreview').replaceChildren();}
$('bannerFiles').onchange=()=>{clearBannerPreviews();for(const file of [...$('bannerFiles').files].slice(0,10)){const url=URL.createObjectURL(file);bannerPreviewUrls.push(url);const img=document.createElement('img');img.src=url;img.alt=file.name;$('bannerPreview').append(img)}};
$('reloadBanners').onclick=()=>run(loadBanners);
$('bannerForm').onsubmit=e=>{e.preventDefault();if(bannerUploads)return;run(async()=>{
 const files=[...$('bannerFiles').files],slot=Number($('bannerSlot').value),title=$('bannerTitle').value.trim();
 if(!files.length||files.length>10)throw new Error('اختَر من صورة واحدة إلى 10 صور');
 // Validate the entire selection before starting any upload.
 for(const file of files)if(!['image/jpeg','image/png','image/webp'].includes(file.type)||file.size>5242880)throw new Error('كل صورة لازم تكون JPG / PNG / WebP وأقل من 5 ميغابايت');
 bannerUploads=true;$('uploadBanners').disabled=true;let done=0;
 try{
  await loadBanners();let order=Math.max(-1,...bannerRows.filter(x=>x.slot===slot).map(x=>x.sort_order));
  if(order+files.length>10000)throw new Error('عدّل ترتيب الصور الحالية قبل الإضافة');
  for(const file of files){
   $('bannerProgress').textContent=`جاري رفع ${done+1} من ${files.length}…`;const jpeg=await bannerJpeg(file),path=crypto.randomUUID()+'.jpg';
   const upload=await bannerBucket.upload(path,jpeg,{contentType:'image/jpeg',upsert:false});if(upload.error)throw upload.error;
   const saved=await db.from('tkt_home_banners').insert({slot,image_path:path,title,sort_order:++order,enabled:true});
   if(saved.error){await bannerBucket.remove([path]);throw saved.error}done++;
  }
  $('bannerForm').reset();clearBannerPreviews();status('تم رفع وتفعيل صور البنر؛ تظهر بالتطبيق خلال 30 ثانية أو عند فتح الرئيسية');
 }catch(e){throw new Error(`${done?`تم حفظ ${done} صورة. `:''}${message(e)}`)}
 finally{bannerUploads=false;$('uploadBanners').disabled=false;$('bannerProgress').textContent=`تم حفظ ${done} من ${files.length} صور`;await loadBanners()}
})};

// Inventory and spin results are determined transactionally by the server.
async function wheelRpc(action,data={}){const {data:result,error}=await db.rpc('tkt_wheel',{p_action:action,p_data:data});if(error){if(error.message.includes('WHEEL_STOCK_CHANGED'))throw new Error('المخزون تغيّر بسبب لفة أو تعديل آخر؛ حدّث الصفحة قبل الحفظ');throw error}return result}
let wheelData={},wheelClaims=[];
async function loadWheel(more=false){
 wheelData=await wheelRpc('admin_snapshot',{status:$('wheelClaimStatus').value,offset:more?wheelClaims.length:0});
 wheelClaims=more?[...wheelClaims,...wheelData.claims]:wheelData.claims;
 $('wheelEnabled').checked=wheelData.enabled;$('wheelMetrics').textContent=`اللفات: ${wheelData.spins} · الجوائز الرابحة: ${wheelData.wins} · بانتظار التسليم: ${wheelData.pending}`;
 $('wheelPrizes').replaceChildren();
 for(const prize of wheelData.prizes){
  const card=text('article','');card.className='banner-item';const title=text('h3',prize.title),info=text('small',`المتوفر: ${prize.remaining} · ${prize.enabled?'مفعلة':'متوقفة'}`);
  const form=document.createElement('form'),quantity=inputField('عدد الجوائز المتوفرة',prize.remaining,'number');quantity.input.min=0;quantity.input.max=100000;quantity.input.required=true;
  const toggle=text('label',''),enabled=document.createElement('input');enabled.type='checkbox';enabled.checked=prize.enabled;toggle.append(enabled,document.createTextNode(' الجائزة فعالة'));
  const save=text('button','حفظ المخزون');save.type='submit';save.disabled=!canEdit('wheel');quantity.input.disabled=!canEdit('wheel');enabled.disabled=!canEdit('wheel');
  form.append(quantity.box,toggle,save);form.onsubmit=e=>{e.preventDefault();run(async()=>{const n=Number(quantity.input.value);if(!Number.isInteger(n)||n<0||n>100000)throw new Error('عدد الجوائز رقم صحيح من 0 إلى 100000');save.disabled=true;try{await wheelRpc('stock',{key:prize.key,remaining:n,enabled:enabled.checked,revision:prize.revision});await loadWheel();status('تم تحديث مخزون '+prize.title)}finally{save.disabled=false}})};
  card.append(title,info,form);$('wheelPrizes').append(card);
 }
 const list=$('wheelClaims');list.replaceChildren();
 for(const claim of wheelClaims){
  const controls=claim.status==='pending'?[button('تأكيد تسليم الجائزة',async()=>{if(!confirm('تأكيد أن الفائز استلم '+claim.prize_title+' فعلياً؟'))return;await wheelRpc('deliver',{id:claim.id});await loadWheel();status('تم تسجيل تسليم الجائزة')})]:[];
  list.append(record(claim.prize_title,[['الفائز',claim.name||'—'],['الهاتف',localPhone(claim.phone)],['رقم الجائزة',claim.id],['وقت الفوز',dates(claim.created_at)],['الحالة',claim.status==='pending'?'بانتظار التسليم':'تم التسليم'],['وقت التسليم',dates(claim.delivered_at)],['اللفة القادمة',dates(new Date(Date.parse(claim.created_at)+259200000).toISOString())]],controls));
 }empty(list);$('moreWheelClaims').hidden=wheelData.claims.length<100;
}
$('reloadWheel').onclick=()=>run(()=>loadWheel());$('moreWheelClaims').onclick=()=>run(()=>loadWheel(true));$('wheelClaimStatus').onchange=()=>run(()=>loadWheel());
$('saveWheelState').onclick=()=>run(async()=>{await wheelRpc('configure',{enabled:$('wheelEnabled').checked});await loadWheel();status(wheelData.enabled?'العجلة مفعّلة':'العجلة متوقفة مؤقتاً')});






let lineRows=[];
const lineKindNames={school:'خط مدرسة',work:'خط عمل',daily:'خط التزام يومي'};
const lineStateNames={pending:'بانتظار موافقة كابتن',accepted:'تم قبول الخط',completed:'انتهت مدة الخط',cancelled:'ملغي'};
const lineRunNames={arrived:'لقد وصل الكابتن',scheduled:'بانتظار الموعد',heading:'الكابتن متوجه',picked_up:'تم استلام الركاب',completed:'وصل الركاب',missed:'لم يُنفّذ'};
const linePayNames={not_due:'الدفع بنهاية مدة الخط',due:'مستحق',customer_confirmed:'الزبون أكد الدفع',paid:'تم الدفع والاستلام'};
const lineTrackMarkers=new Map();
const lineWeek=['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
async function linesRpc(action,data={}){return dashboardRpc('tkt_lines',action,data);}
let lateLineRows=[];
async function lineAlertsRpc(action,data={}){return dashboardRpc('tkt_line_alerts',action,data);}
const lineAlarm=createEmergencyAlarm({fetchCases:async()=>{const rows=await lineAlertsRpc('list');lateLineRows=rows;if(dialogMode==='late-lines')renderLateLines();return rows.map(l=>({id:l.id,status:'open'}));},createAudioContext:typeof(window.AudioContext||window.webkitAudioContext)==='function'?()=>new(window.AudioContext||window.webkitAudioContext)():undefined,onState:s=>{const el=$('lineAlarm');if(!el)return;el.hidden=!s.active;el.textContent=(s.openCount?'⚠ '+s.openCount+' تنبيه تأخير · فتح المتأخرين':'الخطوط المتأخرة')+' · '+(s.enabled?'الصوت مفعّل':'تفعيل الصوت');el.classList.toggle('emergency-notification',s.openCount>0);el.title=s.error||'فتح الخطوط المتأخرة ومعالجة التنبيهات';}});
$('lineAlarm').onclick=()=>{void lineAlarm.arm();return run(openLateLines);};
function renderLateLines(){
 const list=$('lateLineList');if(!list||dialogMode!=='late-lines')return;
 if(!renderCache.changed('late-lines:'+dialogEpoch,lateLineRows))return;
 list.replaceChildren();
 for(const l of lateLineRows){
  const controls=[button('تفاصيل الخط والتتبع',()=>trackLine(l.line_id))];
  if(canEdit('lines'))controls.push(button('تم التعامل',()=>resolveLateLine(l)));
  list.append(record(l.passenger_name||'خط متأخر',[
   ['نوع التأخير',l.stage==='arrival'?'تأخر الوصول':'تأخر استلام الركاب'],['موعد المشوار',dates(l.due_at)],
   ['الكابتن',l.captain_name||'—'],['هاتف الكابتن',localPhone(l.captain_phone)],
   ['الزبون',l.customer_name||'—'],['هاتف الزبون',localPhone(l.customer_phone)],
   ['الانطلاق',l.pickup_name],['الوجهة',l.destination_name],['حالة المشوار',lineRunNames[l.state]]
  ],controls));
 }
 if(!lateLineRows.length)list.append(text('p','ماكو خطوط متأخرة تحتاج معالجة حاليًا. توقف صوت التحذير.'));
}
async function openLateLines(){
 if(!canView('lines'))throw Error('PERMISSION_DENIED');
 const body=openDetail('الخطوط المتأخرة',{name:'lateLines',args:[]});dialogMode='late-lines';
 body.append(text('p','افتح تفاصيل الخط للمتابعة، واضغط «تم التعامل» بعد معالجة الحالة. يبقى الصوت للحالات الأخرى غير المعالجة.'));
 body.append(button('تحديث المتأخرين',()=>lineAlarm.refresh()));
 body.append(Object.assign(text('div',''),{id:'lateLineList'}));
 renderLateLines();await lineAlarm.refresh();
}
async function resolveLateLine(l){
 if(!canEdit('lines'))throw Error('PERMISSION_DENIED');
 await lineAlertsRpc('resolve',{run_id:l.run_id,stage:l.stage});
 lateLineRows=lateLineRows.filter(row=>row.id!==l.id);
 lineAlarm.resolved(l.id);renderLateLines();
 status('تم التعامل مع تنبيه الخط؛ يبقى الإنذار للحالات غير المعالجة.');
 await lineAlarm.refresh();
}
async function loadLines(){const token=requestTracker.next('lines'),rows=await linesRpc('list');if(!requestTracker.current(token))return;lineRows=rows;renderLines();}
function lineFacts(l){const weekly=l.weekly_schedule||{};const shiftFacts=[];for(const [key,title]of [['morning','الدوام الصباحي'],['afternoon','الدوام الظهري']]){const days=Object.entries(weekly).filter(([,value])=>value.shift===key).sort((a,b)=>Number(a[0])-Number(b[0]));if(days.length){const time=days[0][1];shiftFacts.push([title,days.map(([day])=>lineWeek[Number(day)]).join('، ')],[title+' — الانطلاق',displayClock(time.departure)],[title+' — الوصول',displayClock(time.arrival)],[title+' — الرجوع',displayClock(time.return_home)]);}}return [...shiftFacts,['الزبون',l.customer_name||l.customer?.name||'—'],['اسم الراكب',l.passenger_name],['الانطلاق',l.pickup_name],['الوصول',l.destination_name],['عدد أيام الخدمة',l.service_days],['بداية الخط',l.start_date],['آخر يوم خدمة',l.end_date],['الأيام المستبعدة',(l.excluded_days||[]).map(d=>lineWeek[d]).join('، ')||'بدون استبعاد'],['الانطلاق',displayClock(l.departure)],['وقت الوصول',displayClock(l.arrival)],['وقت الرجوع للمنزل',l.return_home?displayClock(l.return_home):'غير محدد'],['أجور كل مدة الخط',money(l.total_price)],['الحالة',lineStateNames[l.status]],['الدفع',linePayNames[l.payment_status]],['تاريخ استلام الأجور',dates(l.paid_at)],['أيام أُنجزت',l.completed_days??'—'],['أيام لم تُنفّذ',l.missed_days??'—'],['أيام متبقية',l.remaining_days??'—'],['الكابتن',l.captain_name||'بانتظار القبول'],['تحذيرات التأخير',l.late_count||0]];}
function renderLines(){if(!renderCache.changed('lines',[lineRows,$('lineSearch').value,$('lineStatus').value]))return;const list=$('lineList'),search=$('lineSearch').value.trim(),filter=$('lineStatus').value;list.replaceChildren();for(const l of lineRows.filter(l=>(!filter||l.status===filter)&&(!search||`${l.customer_name} ${l.passenger_name} ${l.captain_name} ${l.pickup_name} ${l.destination_name}`.includes(search)))){const card=record(lineKindNames[l.kind],lineFacts(l),[button('التفاصيل والتتبع',()=>trackLine(l.id))]);if(l.unresolved_late>0)card.prepend(text('p','⚠ إنذار: الكابتن لم يستلم الركاب بعد موعد الخط بـ5 دقائق'));list.append(card);}empty(list);}
async function trackLine(id){lineTrackMarkers.clear();const body=openDetail('تفاصيل الخط والتتبع');dialogMode='line';dialogKey=id;body.append(Object.assign(text('div',''),{id:'lineTrackMap',className:'admin-map'}),Object.assign(text('div',''),{id:'lineTrackInfo'}),Object.assign(text('div',''),{id:'lineSchedule'}),Object.assign(text('div',''),{id:'lineDocuments'}));dialogMap=mapFor('lineTrackMap');dialogLayer=L.layerGroup().addTo(dialogMap);await updateLineTrack(true);}
async function updateLineTrack(fit=false){if(dialogRefreshing||dialogMode!=='line')return;dialogRefreshing=true;const epoch=dialogEpoch;try{const r=await linesRpc('detail',{id:dialogKey});if(epoch!==dialogEpoch||dialogMode!=='line')return;const l=r.line,bounds=[],seen=new Set();for(const [key,lat,lng,label,color]of [['pickup',l.pickup_lat,l.pickup_lng,'الانطلاق','#e01828'],['destination',l.destination_lat,l.destination_lng,'الوصول','#2878c8'],['captain',r.captain?.lat,r.captain?.lng,'الكابتن','#009a63'],['customer',r.customer?.lat,r.customer?.lng,'الزبون','#7a48b4']]){if(Number.isFinite(lat)&&Number.isFinite(lng)){seen.add(key);let marker=lineTrackMarkers.get(key);if(marker){marker.setLatLng([lat,lng]);}else{marker=L.circleMarker([lat,lng],{radius:9,color,fillOpacity:1}).bindPopup(text('span',label)).addTo(dialogLayer);lineTrackMarkers.set(key,marker);}bounds.push([lat,lng]);}}for(const [key,marker]of lineTrackMarkers)if(!seen.has(key)){dialogLayer.removeLayer(marker);lineTrackMarkers.delete(key);}if(fit&&bounds.length)dialogMap.fitBounds(bounds,{padding:[30,30],maxZoom:16});const info=$('lineTrackInfo');info.replaceChildren(facts(lineFacts({...l,customer_name:r.customer?.name,captain_name:r.captain?.name,late_count:r.runs.filter(x=>x.late_at).length})),facts([['هاتف الزبون',localPhone(r.customer?.phone)],['آخر موقع للزبون',dates(r.customer?.location_at)],['هاتف الكابتن',localPhone(r.captain?.phone)],['آخر موقع للكابتن',dates(r.captain?.location_at)]]));if(r.captain&&(canView('inventory')||canView('users')))info.append(button('عرض الملف الشخصي للكابتن',()=>openUserProfile(r.captain.user_id)));if(r.customer&&(canView('inventory')||canView('users')))info.append(button('عرض الملف الشخصي للزبون',()=>openUserProfile(r.customer.user_id)));if(canEdit('lines')&&['pending','accepted'].includes(l.status))info.append(button('إلغاء الخط',async()=>{const reason=prompt('سبب إلغاء الخط');if(!reason?.trim())return;await linesRpc('cancel',{id:l.id,reason});await updateLineTrack();},'danger'));if(renderCache.changed('line-schedule:'+dialogEpoch,r.runs)){const schedule=$('lineSchedule');schedule.replaceChildren(text('h3','جدول الأيام والتنبيهات'));for(const d of r.runs)schedule.append(record(d.service_date,[['موعد الانطلاق',dates(d.departure_at)],['وقت الوصول',dates(d.arrival_at)],['وقت الرجوع للمنزل',dates(d.return_at)],['الحالة',lineRunNames[d.state]],['إشعار الموعد',dates(d.reminded_at)],['تحذير التأخير',dates(d.late_at)],['استلام الركاب',dates(d.picked_up_at)],['اكتمال المشوار',dates(d.completed_at)]],[]));}if(fit){const docs=$('lineDocuments');docs.replaceChildren(text('h3','الجنسية — مراجعة الإدارة فقط'));for(const [label,path]of [['الوجه',l.front_path],['الخلف',l.back_path]]){if(!path)continue;const signed=await db.storage.from('tkt-line-documents').createSignedUrl(path,300);if(epoch!==dialogEpoch)return;if(signed.error){docs.append(text('p','تعذّر فتح '+label));continue;}const img=document.createElement('img');img.src=signed.data.signedUrl;img.alt='الجنسية '+label;img.className='line-document';docs.append(img);}}}finally{dialogRefreshing=false;}}
$('reloadLines').onclick=()=>run(loadLines);$('lineSearch').oninput=debounceTask(renderLines,150);$('lineStatus').onchange=renderLines;

let profileLineRefreshAt=0;
async function refreshProfileLines(userId,epoch){const report=await linesRpc('profile',{user_id:userId});if(epoch!==dialogEpoch||!$('profileLineReport'))return;profileLineRefreshAt=Date.now();renderProfileLines(report,$('profileLineReport'));}
function renderProfileLines(report,section){if(!renderCache.changed('profile-lines:'+dialogEpoch,report))return;const s=report.summary;section.replaceChildren(text('h3','خطوط الكابتن والجرد المالي'));const metrics=text('div','');metrics.className='metrics';for(const [key,label,isMoney]of [['assigned_lines','كل الخطوط الملتزم بها'],['active_lines','الخطوط الحالية'],['completed_lines','خطوط أنجزها بالكامل'],['ended_lines','خطوط انتهت مدتها'],['cancelled_lines','خطوط ملغية'],['late_lines','خطوط سُجّل تأخر عليها'],['overdue_lines','خطوط متأخر عليها الآن'],['completed_days','مشاوير أُنجزت'],['missed_days','مشاوير لم تُنفّذ'],['due_total','أجور مستحقة غير مستلمة',true],['received_total','أجور استلمها',true]]){const tile=text('div','');tile.className='metric';tile.append(text('strong',isMoney?money(s[key]):new Intl.NumberFormat('en-US').format(s[key]||0)),text('span',label));metrics.append(tile);}section.append(metrics,text('p','آخر تحديث: '+dates(report.server_now)),button('تحديث بيانات الخطوط',()=>refreshProfileLines(report.user_id,dialogEpoch)));for(const l of report.lines){const card=record(`${lineKindNames[l.kind]} · ${l.passenger_name}`,lineFacts(l).concat([['إنذارات حالية',l.unresolved_late],['أيام تأخر عليها',l.late_days]]),[button('تفاصيل الخط والتتبع',()=>trackLine(l.id))]);if(l.unresolved_late>0)card.prepend(text('p','⚠ الكابتن متأخر على هذا الخط الآن'));section.append(card);}if(!report.lines.length)section.append(text('p','ما عنده خطوط ملتزم بها'));if(report.has_more)section.append(text('p','المعروض آخر 100 خط؛ الإحصائيات تشمل جميع الخطوط.'));}

setupEnglishNumbers();

setupTwelveHourInputs();

setupGroupedNumbers();

async function portalRpc(action,data={}){const r=await db.rpc('tkt_captain_portal',{p_action:action,p_data:data});if(r.error)throw r.error;return r.data;}
async function loadPortalSettings(){const value=await portalRpc('admin_get');$('portalAndroidUrl').value=value.android_url||'';$('portalAvailable').checked=value.available;$('portalIosUrl').value=value.ios_url||'';$('portalIosAvailable').checked=Boolean(value.ios_available);$('portalMetrics').textContent=`المسجلون بالموقع: ${value.members} · حسابات لديها اشتراك إشعارات ويب: ${value.subscribed}`;$('portalAnnounce').disabled=Boolean(value.announcement_id)||!canEdit('applications');$('portalSave').disabled=!canEdit('applications');$('portalAnnouncementStatus').textContent=value.announcement_id?'أُرسل إعلان توفر التطبيق للمسجلين.':'';}
$('portalSave').onclick=()=>run(async()=>{await portalRpc('save',{android_url:$('portalAndroidUrl').value.trim(),available:$('portalAvailable').checked,ios_url:$('portalIosUrl').value.trim(),ios_available:$('portalIosAvailable').checked});await loadPortalSettings();status('تم تحديث رابط تحميل التطبيق بالموقع');});
$('portalAnnounce').onclick=()=>run(async()=>{if(!confirm('إرسال إشعار توفر التطبيق إلى المسجلين بالموقع؟'))return;const r=await portalRpc('announce');await loadPortalSettings();status(`تم إدراج الإشعار لـ ${r.queued} حساب. يصل تنبيه المتصفح للأجهزة المفعّل بها الإذن.`);});


$('dashboardMenuClose').onclick=()=>setMenu(false);
$('dashboardMenu').addEventListener('close',()=>{if($('dashboardMenu').open)return;document.body.classList.remove('menu-open');$('menuToggle').setAttribute('aria-expanded','false');$('menuToggle').focus();});
$('dashboardMenu').addEventListener('cancel',e=>{e.preventDefault();requestAppBack(()=>setMenu(false));});
$('dashboardMenu').addEventListener('click',e=>{const menu=$('dashboardMenu');if(e.target===menu){const r=menu.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)setMenu(false);}});
document.addEventListener('contextmenu',e=>{if(!e.target.closest('input,textarea,[contenteditable="true"],.leaflet-container'))e.preventDefault();});
document.addEventListener('dragstart',e=>{if(!e.target.closest('input,textarea,.leaflet-container'))e.preventDefault();});
let dashboardInstallPrompt=null;
window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();dashboardInstallPrompt=e;});
window.addEventListener('appinstalled',()=>{$('dashboardInstall').hidden=true;dashboardInstallPrompt=null;});
if(window.matchMedia('(display-mode: standalone)').matches)$('dashboardInstall').hidden=true;
$('dashboardInstall').onclick=async()=>{if(dashboardInstallPrompt){const prompt=dashboardInstallPrompt;dashboardInstallPrompt=null;await prompt.prompt();await prompt.userChoice;}else{$('dashboardInstallInstructions').textContent=/iPhone|iPad|iPod/.test(navigator.userAgent)?'من Safari اضغط المشاركة، ثم «إضافة إلى الشاشة الرئيسية».':'من قائمة Chrome ⋮ اختار «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية». إذا فاتحه داخل تطبيق ثاني، افتح الرابط أولًا بمتصفح Chrome.';$('dashboardInstallHelp').showModal();}};
$('dashboardInstallClose').onclick=()=>$('dashboardInstallHelp').close();
if('serviceWorker' in navigator)navigator.serviceWorker.register('./firebase-messaging-sw.js',{updateViaCache:'none'}).catch(()=>{});

$('newStaffPage').onclick=()=>{clearStaffForm();openSectionScreen($('staffEditor'),'إضافة موظف جديد');};


let logoutConfirmAt=0;const logoutAction=$('logout').onclick;$('logout').onclick=()=>{if(Date.now()-logoutConfirmAt<2200)return logoutAction();logoutConfirmAt=Date.now();status('اضغط تسجيل الخروج مرة ثانية لتأكيد الخروج');};

const detailActions={accountDelete:(kind,id)=>accountAdmin.open(kind,id),exchangeCredit:id=>exchangesPage.openCredit(id),exchangeSettle:id=>exchangesPage.openSettle(id),lateLines:openLateLines,notifications:showNotificationInbox,exchangeMetric:kind=>exchangesPage.openMetric(kind),couponHistory:code=>couponRewards.openHistory(code)};
{const original=openUserProfile;openUserProfile=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'openUserProfile',args};return result;}finally{navigation?.end();}};detailActions['openUserProfile']=openUserProfile;}
{const original=trackRide;trackRide=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'trackRide',args};return result;}finally{navigation?.end();}};detailActions['trackRide']=trackRide;}
{const original=trackLine;trackLine=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'trackLine',args};return result;}finally{navigation?.end();}};detailActions['trackLine']=trackLine;}
{const original=chat;chat=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'chat',args};return result;}finally{navigation?.end();}};detailActions['chat']=chat;}
{const original=ledger;ledger=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'ledger',args};return result;}finally{navigation?.end();}};detailActions['ledger']=ledger;}
{const original=applicationDetail;applicationDetail=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'applicationDetail',args};return result;}finally{navigation?.end();}};detailActions['applicationDetail']=applicationDetail;}
{const original=editUser;editUser=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'editUser',args};return result;}finally{navigation?.end();}};detailActions['editUser']=editUser;}
{const original=editSubscription;editSubscription=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'editSubscription',args};return result;}finally{navigation?.end();}};detailActions['editSubscription']=editSubscription;}
{const original=moneyAction;moneyAction=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'moneyAction',args};return result;}finally{navigation?.end();}};detailActions['moneyAction']=moneyAction;}
{const original=editFavorite;editFavorite=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'editFavorite',args};return result;}finally{navigation?.end();}};detailActions['editFavorite']=editFavorite;}
{const original=resetPassword;resetPassword=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'resetPassword',args};return result;}finally{navigation?.end();}};detailActions['resetPassword']=resetPassword;}
{const original=resetStaffPassword;resetStaffPassword=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'resetStaffPassword',args};return result;}finally{navigation?.end();}};detailActions['resetStaffPassword']=resetStaffPassword;}
{const original=editBanner;editBanner=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'editBanner',args};return result;}finally{navigation?.end();}};detailActions['editBanner']=editBanner;}
{const original=openEmergency;openEmergency=async(...args)=>{const navigation=appNavigation;navigation?.begin();try{const result=await original(...args);detailAction={name:'openEmergency',args};return result;}finally{navigation?.end();}};detailActions['openEmergency']=openEmergency;}
function captureDashboard(){
 const filters={};for(const el of document.querySelectorAll('input[type="search"],input[id$="Search"],select[id]'))if(el.id&&!el.closest('form')&&!el.id.includes('Password'))filters[el.id]=el.value;
 const sectionScreens=getSectionScreens();
 return {loaded:{users:users.length,rides:rides.length,applications:applications.length,inventory:inventoryItems.length},focus:document.activeElement?.id||null,operations:operations.getState(),page:activePage,scroll:window.scrollY,scrolls:{detailDialog:$('detailDialog').scrollTop,...Object.fromEntries(sectionScreens.map(s=>[s.id,s.scroll]))},sections:sectionScreens,detail:detailAction?.name==='globalSearch'?{name:'globalSearch',args:globalSearch.getState()}:detailAction,exchange:exchangesPage.getState(),inventoryCategory,staffUser:sectionScreens.some(s=>s.id==='staffEditor')?(editingStaff?.user_id||null):null,reward:couponRewards.getState?.(),filters};
}
async function restoreDashboard(state){
 operations.restore(state.operations);closeDetail();closeAllSectionScreens();const page=canView(state.page)?state.page:permissionPages.find(([key])=>canView(key))?.[0];if(!page)return;showPage(page);inventoryCategory=state.inventoryCategory||inventoryCategory;for(const [id,value]of Object.entries(state.filters||{})){const el=$(id);if(el)el.value=value;}await loadPage(page);
 for(const [id,value]of Object.entries(state.filters||{})){const el=$(id);if(el)el.value=value;}supportSearch=$('supportSearch').value.trim();supportFilter=$('supportFilter').value;if(page==='inventory')await loadInventoryRows();else if(page==='users')renderUsers();else if(page==='rides')renderRides();else if(page==='finance')renderWallets();else if(page==='staff')renderStaff();else if(page==='lines')renderLines();else if(page==='support')renderSupport();else if(page==='exchanges')await exchangesPage.load();
 const savedCounts=state.loaded||{};for(const [name,count,loadMore]of [['users',()=>users.length,()=>loadUsers(true)],['rides',()=>rides.length,()=>loadRides(true)],['applications',()=>applications.length,()=>loadApplications(true)],['inventory',()=>inventoryItems.length,()=>loadInventoryRows(true)]]){if(page!==name)continue;while(count()<(savedCounts[name]||0)){const before=count();await loadMore();if(count()<=before)break;}}
 if(state.exchange?.id&&page==='exchanges')await exchangesPage.restore(state.exchange);
 if(state.staffUser&&page==='staff'){const user=staffRows.find(s=>s.user_id===state.staffUser);if(user)editStaff(user);}
 if(state.reward&&page==='rewards')couponRewards.restore?.(state.reward);
 for(const screen of state.sections||[]){const el=$(screen.id);if(el){const dialog=openSectionScreen(el,screen.title);dialog.scrollTop=screen.scroll||0;}}
 if(state.detail&&detailActions[state.detail.name])await detailActions[state.detail.name](...(state.detail.args||[]));
 setMenu(false,false);
}
async function startDashboardNavigation(){if(appNavigation)return;const user=(await db.auth.getUser()).data.user;if(!user)return;appNavigation=createAppNavigation({key:'tkt-admin-navigation:'+user.id,capture:captureDashboard,restore:restoreDashboard,notify:status,onRestoring:value=>{$('navigationLoading').hidden=!value;document.body.classList.toggle('navigation-restoring',value);}});await appNavigation.start();}

const operations=createOperations({document,rpc:(a,d)=>dashboardRpc('tkt_operations',a,d),exchangeRpc:(a,d)=>dashboardRpc('tkt_exchange',a,d),openDetail,button,text,money,dates,canView,canEdit,notify:status,run,openUser:openUserProfile,openRide:trackRide,openLine:trackLine,openApplication:async id=>{const data=await applicationRpc('list',{status:'pending',limit:500});const row=data.find(a=>a.user_id===id);if(!row)throw Error('الطلب غير متاح');await applicationDetail(row);},openExchange:async id=>{showPage('exchanges');await exchangesPage.restore({id});},openChat:chat,loadSupport,getRooms:()=>[...supportRooms.map(r=>({...r,kind:'support'})),...recovery.map(r=>({...r,kind:'recovery'})),...exchangeRooms.map(r=>({...r,kind:'exchange'}))],getUser:()=>notificationUser,renderSupport:()=>{renderCache.clear();renderSupport();}});
for(const name of ['center','renewals','statement','demand','watch','audit','editWorkflow'])detailActions['operations:'+name]=(...args)=>operations[name](...args);

const globalSearch=createGlobalSearch({document,search:async(q,kind,offset)=>{const r=await db.rpc('tkt_global_search',{p_query:q,p_kind:kind,p_offset:offset});if(r.error)throw r.error;return r.data;},openDetail,button,text,dates,run,openUser:openUserProfile,openRide:trackRide,openLine:trackLine,openExchange:async id=>{appNavigation?.save();showPage('exchanges',false);await exchangesPage.restore({id});}});
detailActions.globalSearch=(...args)=>globalSearch.show(...args);$('globalSearchButton').onclick=()=>run(()=>globalSearch.show());
document.addEventListener('keydown',event=>{if((event.ctrlKey||event.metaKey)&&event.shiftKey&&event.key.toLowerCase()==='f'&&!event.altKey&&!event.isComposing&&!$('admin').hidden){event.preventDefault();if(!event.repeat)run(()=>globalSearch.show());}});

setupKeyboardShortcuts({document,window,menu:$('menuToggle'),notifications:$('notifications'),help:$('keyboardHelp'),notify:status,onSearch(id){const actions={rideSearch:loadRides,userSearch:loadUsers,applicationSearch:loadApplications,walletSearch:renderWallets,favoriteSearch:renderFavorites,lineSearch:renderLines,staffSearch:renderStaff};if(!actions[id])return false;run(actions[id]);return true;}});
const {data:{session}}=await db.auth.getSession();if(session){await run(load);const id=new URL(window.location.href).searchParams.get('notice');if(id){const n=notificationRows.find(n=>n.id===id);if(n)await run(()=>openNotification(n));}}

setupPhoneActions(document);
