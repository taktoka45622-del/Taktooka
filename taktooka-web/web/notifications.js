(()=>{
 let sdk,unsub,pending=[];
 let config;
 const deliver=(data,clicked=false)=>{if(typeof window.tktWebMessage==='function')window.tktWebMessage(JSON.stringify(data),clicked);else pending.push([data,clicked]);};
 window.tktEnablePush=async ask=>{
  if(!('Notification'in window)||!('serviceWorker'in navigator))throw Error('WEB_PUSH_UNSUPPORTED');
  if(ask&&await Notification.requestPermission()!=='granted')throw Error('WEB_PUSH_DENIED');
  if(Notification.permission!=='granted')return '';
  sdk??=Promise.all([import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js'),import('https://www.gstatic.com/firebasejs/11.10.0/firebase-messaging.js')]);
  const [appApi,msgApi]=await sdk;if(!await msgApi.isSupported())throw Error('WEB_PUSH_UNSUPPORTED');
  config??=await fetch(new URL('../firebase-config.json',document.baseURI)).then(r=>{if(!r.ok)throw Error('WEB_PUSH_CONFIG');return r.json();});
  const app=appApi.getApps().find(a=>a.name==='taktooka-web')||appApi.initializeApp(config,'taktooka-web');
  const registration=await navigator.serviceWorker.register(new URL('firebase-messaging-sw.js',document.baseURI),{scope:new URL('./',document.baseURI).pathname,updateViaCache:'none'});
  const worker=registration.installing||registration.waiting||registration.active;
  if(worker&&worker.state!=='activated')await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('WEB_PUSH_TIMEOUT')),20000);worker.addEventListener('statechange',()=>{if(worker.state==='activated'){clearTimeout(timer);resolve();}});});
  const messaging=msgApi.getMessaging(app);unsub?.();unsub=msgApi.onMessage(messaging,payload=>deliver(payload.data||{}));
  for(const [data,clicked]of pending.splice(0))deliver(data,clicked);
  return await msgApi.getToken(messaging,{serviceWorkerRegistration:registration});
 };
 if('serviceWorker'in navigator)navigator.serviceWorker.addEventListener('message',event=>{if(event.data?.type==='tkt-web-click')deliver(event.data.data,true);});
 let wake;
 async function keepAwake(){if(document.visibilityState==='visible'&&navigator.wakeLock){try{wake=await navigator.wakeLock.request('screen');}catch{}}}
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')keepAwake();});
 document.addEventListener('pointerdown',keepAwake,{once:true});
})();
