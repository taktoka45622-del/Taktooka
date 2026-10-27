type Notice={type?:string};
type Step={name?:string;distance?:number;maneuver?:{type?:string;modifier?:string};notifications?:Notice[];intersections?:{mapbox_streets_v8?:{class?:string}}[]};
type Route={distance:number;duration:number;geometry:{type:string;coordinates:number[][]};legs?:{steps?:Step[];notifications?:Notice[]}[];notifications?:Notice[]};
function valid(r:Route):boolean{
 if(!r||!Number.isFinite(r.distance)||r.distance<=0||r.distance>2147483647||!Number.isFinite(r.duration)||r.duration<=0||r.geometry?.type!=='LineString'||!Array.isArray(r.geometry.coordinates)||r.geometry.coordinates.length<2||r.geometry.coordinates.some(p=>!Array.isArray(p)||p.length<2||!p.every(Number.isFinite)))return false;
 const notices=[...(r.notifications??[]),...(r.legs??[]).flatMap(l=>[...(l.notifications??[]),...(l.steps??[]).flatMap(s=>s.notifications??[])])];
 return !notices.some(n=>n.type==='violation');
}
function score(r:Route):number{
 const steps=(r.legs??[]).flatMap(l=>l.steps??[]);
 let penalty=0;
 for(const s of steps){
  const type=s.maneuver?.type,modifier=s.maneuver?.modifier;
  if(type==='depart'||type==='arrive')continue;
  if(modifier==='uturn')penalty+=180;
  else if(['turn','fork','end of road','roundabout','rotary','roundabout turn'].includes(type??'')&&modifier!=='straight')penalty+=45;
  // Road class is provider evidence of importance, not physical width or lanes.
  const weights:Record<string,number>={primary:0,primary_link:0.1,secondary:0.15,secondary_link:0.2,tertiary:0.45,tertiary_link:0.5,street:1,street_limited:1.5,service:2,path:3};
  const classes=(s.intersections??[]).map(i=>i.mapbox_streets_v8?.class).filter((c):c is string=>!!c);
  const cost=classes.length ? classes.reduce((sum,c)=>sum+(weights[c]??0.7),0)/classes.length : 0.7;
  penalty+=(s.distance??0)*cost;

 }
 return r.distance+penalty;
}
// Prefer main streets among reasonable alternatives; keep access roads usable.
export function readRoute(data:{code?:string;routes?:Route[]}):Route{
 if(data.code!=='Ok')throw new Error('ROUTE_UNAVAILABLE');
 const safe=(data.routes??[]).filter(valid);
 if(!safe.length)throw new Error('ROUTE_UNAVAILABLE');
 const shortest=Math.min(...safe.map(r=>r.distance));
 const candidates=safe.filter(r=>r.distance<=shortest+Math.min(shortest*0.25,750));
 return candidates.sort((a,b)=>score(a)-score(b)||a.distance-b.distance||a.duration-b.duration)[0];
}
