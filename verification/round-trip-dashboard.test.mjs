import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createRenderCache} from '../dist/performance.js';

const file=process.argv[2]||new URL('../src/app.js',import.meta.url);
const source=fs.readFileSync(file,'utf8');
const helpers=source.slice(source.indexOf('function tripKind('),source.indexOf('async function pricingRpc('));
const listCode=source.slice(source.indexOf('function renderRides('),source.indexOf('async function trackRide('));
const trackCode=source.slice(source.indexOf('async function updateTrack('),source.indexOf('\nasync function ',source.indexOf('async function updateTrack(')+10));
const now=Date.parse('2026-10-13T02:00:00Z');
const geometry={type:'LineString',coordinates:[[44.4,33.5],[44.41,33.51]]};
const reverse={type:'LineString',coordinates:[[44.41,33.51],[44.4,33.5]]};
const ride={id:'test-ride',round_trip:true,wait_minutes:10,waiting_fee:250,fare:2250,
 status:'in_progress',round_trip_stage:'waiting',wait_started_at:'2026-10-13T01:55:00Z',
 pickup:[33.5,44.4],destination:[33.51,44.41],pickup_name:'البيت',destination_name:'السوق',
 route_distance_m:1000,return_distance_m:1200,distance_m:2200,duration_s:870,geometry,return_geometry:reverse};
const elements=new Map();
function element(id){if(!elements.has(id))elements.set(id,{children:[],textContent:'',replaceChildren(...nodes){this.children=nodes;},append(node){this.children.push(node);}});return elements.get(id);}
const drawn=[];
const layer=()=>({bindPopup(){return this;},addTo(){return this;},getBounds(){return {isValid:()=>true,getSouthWest:()=>[33.5,44.4],getNorthEast:()=>[33.51,44.41]};}});
const context=vm.createContext({renderCache:createRenderCache(),rideMovingMarker:null,serverTime:now,Date,Number,String,Math,Set,
 stateNames:{in_progress:'الرحلة جارية',completed:'مكتملة',cancelled:'ملغية'},
 money:n=>new Intl.NumberFormat('en-US').format(n)+' د.ع',dates:v=>v||'—',
 rides:[ride,{id:'one-way',status:'completed',fare:1000}],activeStates:['in_progress'],
 $:element,button:(label,action)=>({label,action}),record:(title,rows,controls)=>({title,rows,controls}),
 empty:()=>{},localPhone:v=>v||'',trackRide:()=>{},manage:async()=>({ride,captain:null,offers:[],server_now:new Date(now).toISOString()}),
 facts:rows=>rows,text:(type,value)=>({type,value}),
 dialogRefreshing:false,dialogMode:'track',dialogEpoch:1,dialogKey:'test-ride',
 dialogLayer:{clearLayers(){}},dialogMap:{fitBounds(){}},
 L:{geoJSON:(g,options)=>{drawn.push({g,options});return layer();},circleMarker:layer}});
vm.runInContext(helpers+'\n'+listCode+'\n'+trackCode,context);
const getFacts=r=>new Map(context.tripFacts(r,true));
let facts=getFacts(ride);
assert.equal(facts.get('نوع المشوار'),'ذهاب وإياب');
assert.equal(facts.get('كروة الذهاب'),'1,000 د.ع');
assert.equal(facts.get('كروة الإياب'),'1,000 د.ع');
assert.equal(facts.get('أجرة الانتظار'),'250 د.ع');
assert.equal(facts.get('الكروة مع الانتظار'),'2,250 د.ع');
assert.equal(facts.get('وقت الانتظار المحدد'),'10 دقيقة');
assert.equal(facts.get('الانتظار المتبقي'),'05:00');
assert.equal(facts.get('الرجعة إلى'),'البيت');
assert.equal(facts.get('مسافة الإياب'),'1.20 كم');
assert.equal(getFacts({...ride,wait_minutes:15,waiting_fee:500,fare:2500}).get('كروة الذهاب'),'1,000 د.ع');
assert.equal(context.tripStage({...ride,status:'completed'}),'اكتمل الذهاب والإياب');
assert.equal(context.tripStage({...ride,status:'cancelled'}),'ملغية');
assert.equal(getFacts({...ride,wait_started_at:'2026-10-13T01:00:00Z'}).get('الانتظار المتبقي'),'انتهى وقت الانتظار المحدد');
assert.equal(getFacts({round_trip:false}).size,1);
assert.equal(context.tripMapData(ride).lines.length,2);
const returning=context.tripMapData({...ride,round_trip_stage:'returning',geometry:reverse});
assert.equal(returning.lines.length,1);
assert.equal(returning.points[0][1],'الوصول · الرجعة');
assert.equal(returning.points[1][1],'الانطلاق · الرجعة');
context.renderRides();
assert.equal(element('rideList').children.length,2);
assert.equal(new Map(element('rideList').children[0].rows).get('أجرة الانتظار'),'250 د.ع');
await context.updateTrack(true);
assert.equal(drawn.length,2);
assert.equal(drawn[1].options.style.color,'#2878c8');
assert.equal(new Map(element('rideTrackInfo').children[0]).get('كروة الإياب'),'1,000 د.ع');
assert.match(element('rideTrackLegend').textContent,/مسار الرجعة/);
await context.updateTrack(false);
assert.equal(drawn.length,2,'unchanged route geometry should not be redrawn');
console.log('25 round-trip dashboard checks passed:',String(file));
