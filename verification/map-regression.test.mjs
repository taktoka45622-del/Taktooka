import vm from 'node:vm';
import {JSDOM} from 'jsdom';import fs from 'node:fs';import assert from 'node:assert/strict';
const dom=new JSDOM('<div id="body"></div>'),document=dom.window.document;
const appSource=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8');const source=appSource.match(/let profileLiveChannel[^\n]+/)[0]+'\n'+appSource.slice(appSource.indexOf('function stopCaptainProfile(){'),appSource.indexOf('function permissionEditor('));
const text=(tag,value)=>Object.assign(document.createElement(tag),{textContent:value}),$=id=>document.getElementById(id);
const button=(label,fn)=>{const b=text('button',label);b.onclick=fn;return b;};
const gpsAt=new Date().toISOString();let data={captain:{name:'<img onerror=alert(1)>',online:true,lat:33.3,lng:44.4,location_at:gpsAt},documents_allowed:true,documents:{id_front:'front',id_back:'back'},server_now:gpsAt};
let removed=0,clock=0,frames=[],markerCount=0,pans=0;
const map={setView(){return this},panTo(){pans++;return this},on(){return this},invalidateSize(){}};
const L={divIcon:opts=>opts,marker(point){markerCount++;return {point:[...point],addTo(){return this},bindPopup(){return this},getLatLng(){return {lat:this.point[0],lng:this.point[1]}},setLatLng(p){this.point=[...p];return this}};}};
const db={from:()=>({select(){return this},eq(){return this},maybeSingle:async()=>({data:{documents:data.documents},error:null})}),channel:()=>({on(){return this},subscribe(){return this}}),removeChannel:()=>removed++,storage:{from:()=>({createSignedUrl:async path=>({data:{signedUrl:'https://private.test/'+path},error:null})})}};
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const access={owner:true};
const api=await new AsyncFunction('dashboardRpc','dashboardAccess','document','$','text','button','db','L','mapFor','dates','scheduleLiveRefresh','performance','requestAnimationFrame','cancelAnimationFrame',`function canView(){return true;}function status(){}async function refreshProfileLines(){throw new Error("LINES_OFFLINE");}let profileLineRefreshAt=0;let dialogEpoch=1,dialogMode=null,dialogKey=null,dialogMap=null,dialogRefreshing=false;${source};return {startCaptainProfile,updateCaptainProfile,applyCaptainProfileLocation,stopCaptainProfile,loadCaptainIdentity,getMarker:()=>profileMarker,close:()=>{dialogEpoch++;stopCaptainProfile();},setEpoch:()=>dialogEpoch};`)(async()=>({profile:data.captain}),access,document,$,text,button,db,L,()=>map,v=>v,()=>{}, {now:()=>clock},fn=>(frames.push(fn),frames.length),()=>{frames=[]});
api.startCaptainProfile('captain',$('body'),1);await new Promise(setImmediate);await new Promise(setImmediate);
assert.equal($('body').querySelectorAll('.captain-identity-gallery img').length,2);assert.equal($('body').querySelector('img[onerror]'),null);assert.equal(markerCount,1);assert.match($('captainProfileStatus').textContent,/مباشر/);
data={...data,captain:{...data.captain,lat:33.31,lng:44.41,location_at:new Date(Date.parse(gpsAt)+1000).toISOString()}};await api.updateCaptainProfile();clock=1000;const queued=frames;frames=[];queued.forEach(fn=>fn());assert.deepEqual(api.getMarker().point,[33.31,44.41]);assert.equal(markerCount,1);assert.equal(pans,1);
api.applyCaptainProfileLocation({...data,captain:{...data.captain,lat:10,location_at:new Date(Date.parse(gpsAt)-1000).toISOString()}},1);assert.equal(api.getMarker().point[0],33.31);
api.applyCaptainProfileLocation({...data,server_now:new Date(Date.parse(gpsAt)+60000).toISOString()},1);assert.match($('captainProfileStatus').textContent,/متأخر/);
document.body.append(Object.assign(document.createElement('section'),{id:'profileLineReport'}));data={...data,captain:{...data.captain,online:false}};await api.updateCaptainProfile();assert.match($('captainProfileStatus').textContent,/غير متصل/);
access.owner=false;access.permissions={};await api.loadCaptainIdentity('captain',document.querySelector('.captain-identity-gallery'),1);assert.equal(document.querySelectorAll('.captain-identity-gallery img').length,0);assert.match(document.querySelector('.captain-identity-gallery').textContent,/صلاحية تسجيل المركبات/);
access.owner=true;data={...data,documents:{id_front:'front'}};await api.loadCaptainIdentity('captain',document.querySelector('.captain-identity-gallery'),1);assert.equal(document.querySelectorAll('.captain-identity-gallery img').length,1);assert.match(document.querySelector('.captain-identity-gallery').textContent,/لم تُرفع/);
api.close();assert.equal(removed,1);assert.equal(api.getMarker(),null);
console.log('Captain profile UI checks passed: identity thumbnails, live marker movement, map continuity, stale/offline state, old GPS rejection and cleanup');

const definitions=appSource.slice(appSource.indexOf('function mapFor('),appSource.indexOf('function captainMarker('));
const mapDefinition=definitions.split('\n')[0];
const constructionCalls=[],pendingFrames=[];
const mapContext=vm.createContext({document,requestAnimationFrame:fn=>pendingFrames.push(fn),L:{
  map:(id,options)=>{constructionCalls.push({id,options});return {setView(){return this;},getContainer:()=>document.getElementById(id),invalidateSize(){constructionCalls.push({resize:id});}};},
  tileLayer:(url,options)=>{constructionCalls.push({url,options});return {addTo(){}};},
}});
vm.runInContext(mapDefinition,mapContext);
for(const id of ['map','liveMap','rideTrackMap','favoriteMap','captainProfileMap','lineTrackMap']){
  const node=Object.assign(document.createElement('div'),{id});document.body.append(node);
  mapContext.mapFor(id);
}
for(const frame of pendingFrames.splice(0))frame();
assert.equal(constructionCalls.filter(c=>c.resize).length,6);
for(const layer of constructionCalls.filter(c=>c.url)){
  assert.equal(layer.options.maxNativeZoom,19);
  assert.equal(layer.options.maxZoom,19);
  assert.equal(layer.options.updateWhenIdle,true);
  assert.match(layer.options.attribution,/OpenStreetMap/);
}
mapContext.mapFor('favoriteMap');document.getElementById('favoriteMap').remove();
for(const frame of pendingFrames.splice(0))frame();
assert.equal(constructionCalls.filter(c=>c.resize==='favoriteMap').length,1,'closed map must not be resized');
console.log('All six dashboard map constructors passed: native zoom, attribution, shared tiles and safe dialog resize');
