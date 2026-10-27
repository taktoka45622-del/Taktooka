export function createEmergencyAlarm({fetchCases,onState,createAudioContext,setIntervalFn=setInterval,clearIntervalFn=clearInterval}){
 let userId=null,epoch=0,revision=0,timer=null,pending=new Set(),closed=new Set(),audio=null,source=null,polling=null,pollAgain=false,error=null;
 const supported=typeof createAudioContext==='function';
 function emit(){onState?.({active:!!userId,openCount:pending.size,enabled:audio?.state==='running',supported,error});}
 function stopSound(){if(source){try{source.stop();source.disconnect();}catch(_){}source=null;}}
 function syncSound(){
  if(!userId||pending.size===0){stopSound();emit();return;}
  if(audio?.state==='running'&&!source){
   const rate=audio.sampleRate,buffer=audio.createBuffer(1,rate*2,rate),samples=buffer.getChannelData(0);let phase=0;
   for(let i=0;i<samples.length;i++){const time=i/rate,frequency=800+300*Math.sin(2*Math.PI*time);phase+=2*Math.PI*frequency/rate;const fade=Math.min(1,time/0.06,(2-time)/0.06);samples[i]=0.2*Math.sin(phase)*fade;}
   source=audio.createBufferSource();source.buffer=buffer;source.loop=true;source.connect(audio.destination);source.start();
  }
  emit();
 }
 async function arm(){
  if(!supported)return emit();
  try{if(!audio){audio=createAudioContext();audio.onstatechange=syncSound;}if(audio.state!=='running')await audio.resume();error=null;syncSound();}
  catch(_){error='اضغط تفعيل صوت الطوارئ للسماح بالصوت';emit();}
 }
 async function refresh(){
  if(!userId)return;
  if(polling){pollAgain=true;return polling;}
  const requestEpoch=epoch,requestRevision=revision,requestUser=userId;
  const request=Promise.resolve().then(async()=>{try{const rows=await fetchCases(requestUser);if(requestEpoch!==epoch||requestUser!==userId)return;
   if(requestRevision!==revision){pollAgain=true;return;}
   for(const row of rows)if(row.status==='resolved')closed.add(row.id);pending=new Set(rows.filter(row=>row.status==='open').map(row=>row.id));error=null;syncSound();
  }catch(_){if(requestEpoch===epoch){error='تعذر تحديث حالات الطوارئ؛ الإنذار يبقى للحالات المفتوحة';emit();}}
  finally{if(polling===request)polling=null;if(pollAgain&&requestEpoch===epoch){pollAgain=false;queueMicrotask(()=>refresh());}}});
  polling=request;return request;
 }
 function stop(){epoch++;revision++;userId=null;pending.clear();closed.clear();pollAgain=false;if(timer)clearIntervalFn(timer);timer=null;polling=null;error=null;stopSound();emit();}
 async function start(id){stop();userId=id;emit();timer=setIntervalFn(()=>refresh(),3000);await refresh();}
 function notify(id){if(!userId||!id||closed.has(id))return;revision++;pending.add(id);syncSound();refresh();}
 function resolved(id){if(!userId)return;revision++;closed.add(id);pending.delete(id);syncSound();refresh();}
 return {start,stop,arm,refresh,notify,resolved};
}
