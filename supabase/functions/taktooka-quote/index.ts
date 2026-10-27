import {createClient} from 'npm:@supabase/supabase-js@2.95.3';
import {readRoute} from './route.ts';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{...cors,'Content-Type':'application/json'}});
const valid=(p:unknown):p is [number,number]=>Array.isArray(p)&&p.length===2&&p.every(x=>typeof x==='number'&&Number.isFinite(x))&&p[0]>=29&&p[0]<=38&&p[1]>=38&&p[1]<=49;
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 try{
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const token=(req.headers.get('Authorization')??'').replace(/^Bearer\s+/i,'');
  const {data:{user},error:authError}=await db.auth.getUser(token);
  if(authError||!user)return reply({error:'AUTH_REQUIRED'},401);
  const body=await req.json();let pickup=body.pickup;
  if(body.ride_id){
   const {data:ride,error}=await db.from('tkt_rides').select('pickup,rider_id,status').eq('id',body.ride_id).eq('rider_id',user.id).maybeSingle();
   if(error||!ride||!['pending','accepted','arrived','in_progress'].includes(ride.status))return reply({error:'RIDE_UNAVAILABLE'},409);
   pickup=ride.pickup;
  }
  if(!valid(pickup)||!valid(body.destination))return reply({error:'INVALID_POINTS'},400);
  const [{data:profile},{count},{data:config,error:configError}]=await Promise.all([
   db.from('tkt_profiles').select('blocked,captain,name,phone').eq('user_id',user.id).maybeSingle(),
   db.from('tkt_quotes').select('id',{count:'exact',head:true}).eq('user_id',user.id).gte('created_at',new Date(Date.now()-60000).toISOString()),
   db.rpc('tkt_route_config'),
  ]);
  if(!profile||profile.blocked||profile.captain||!profile.name||!profile.phone)return reply({error:'RIDER_PROFILE_REQUIRED'},403);
  // Reuse only an unbooked quote for these exact points. Repeated taps and
  // retries must not burn the per-user routing allowance or reuse an old ride.
  if(!body.ride_id){
   const {data:cached}=await db.from('tkt_quotes').select('*').eq('user_id',user.id)
    .eq('pickup',JSON.stringify(pickup)).eq('destination',JSON.stringify(body.destination))
    .is('change_ride_id',null).gte('created_at',new Date(Date.now()-45000).toISOString())
    .gt('expires_at',new Date(Date.now()+10000).toISOString())
    .order('created_at',{ascending:false}).limit(1).maybeSingle();
   if(cached){
    const {data:booked,error:bookedError}=await db.from('tkt_rides').select('id').eq('quote_id',cached.id).maybeSingle();
    if(!bookedError&&!booked)return reply(cached);
   }
  }
  if((count??0)>=6)return reply({error:'RATE_LIMIT'},429);
  if(configError||!config.mapbox_token)throw new Error('ROUTE_UNAVAILABLE');
  const url=new URL(`https://api.mapbox.com/directions/v5/mapbox/driving/${pickup[1]},${pickup[0]};${body.destination[1]},${body.destination[0]}`);
  url.search=new URLSearchParams({access_token:config.mapbox_token,overview:'full',geometries:'geojson',steps:'true',exclude:'motorway,toll,ferry',alternatives:'true',radiuses:'75;75',alley_bias:'-1',continue_straight:'true'}).toString();
  const response=await fetch(url,{signal:AbortSignal.timeout(12000)});
  if(!response.ok)throw new Error('ROUTE_UNAVAILABLE');
  const route=readRoute(await response.json());
  const {data:quote,error}=await db.rpc('tkt_route_quote',{p_user:user.id,p_data:{pickup,destination:body.destination,ride_id:body.ride_id??null,geometry:route.geometry,distance_m:route.distance,duration_s:Math.max(1,Math.ceil(route.duration)),route_provider:'mapbox-driving-no-motorway'}});
  if(error){
   if(error.message==='OUTSIDE_SERVICE'){
    const coverageMessage=error.details==='pickup'?'نقطة الانطلاق خارج الحدود المحفوظة بالخريطة':error.details==='destination'?'الوجهة خارج الحدود المحفوظة بالخريطة':'المنطقة المحددة خارج الحدود المحفوظة بالخريطة';
    return reply({error:coverageMessage,code:'OUTSIDE_SERVICE',outside:error.details},422);
   }
   return reply({error:['RATE_LIMIT','RIDE_UNAVAILABLE','RIDER_PROFILE_REQUIRED','DESTINATION_CASH_ONLY'].includes(error.message)?error.message:'ROUTE_UNAVAILABLE'},422);
  }
  return reply(quote);
 }catch{return reply({error:'ROUTE_UNAVAILABLE'},503);}
});
