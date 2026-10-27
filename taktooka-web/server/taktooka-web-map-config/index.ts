import {createClient} from 'npm:@supabase/supabase-js@2.95.3';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async request=>{
 if(request.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(request.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 try{
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const bearer=request.headers.get('authorization')||'';
  if(!bearer.startsWith('Bearer '))return reply({error:'AUTH_REQUIRED'},401);
  const {data:identity,error}=await db.auth.getUser(bearer.slice(7));
  if(error||!identity.user)return reply({error:'AUTH_REQUIRED'},401);
  const {data:profile}=await db.from('tkt_profiles').select('blocked').eq('user_id',identity.user.id).maybeSingle();
  if(!profile||profile.blocked)return reply({error:'ACCOUNT_BLOCKED'},403);
  const {data:config,error:configError}=await db.rpc('tkt_route_config');
  if(configError||typeof config?.mapbox_token!=='string'||!config.mapbox_token.startsWith('pk.'))return reply({error:'MAP_UNAVAILABLE'},503);
  return reply({public_token:config.mapbox_token});
 }catch{return reply({error:'MAP_UNAVAILABLE'},503)}
});
