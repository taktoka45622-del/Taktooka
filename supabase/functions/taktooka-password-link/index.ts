import {createClient} from 'npm:@supabase/supabase-js@2.95.3';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
const hash=async(v:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v)))).map(x=>x.toString(16).padStart(2,'0')).join('');
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 try{
  const body=await req.json(),url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const service=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  if(body.op==='issue'){
   const authorization=req.headers.get('authorization')||'';
   const {data:identity,error:authError}=await service.auth.getUser(authorization.replace(/^Bearer /,''));
   if(authError||!identity.user)return reply({error:'AUTH_REQUIRED'},401);
   const caller=createClient(url,key,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
   const {data:target,error}=await caller.rpc('tkt_manage',{p_action:'reset_target',p_data:{user_id:body.user_id,phone:body.phone}});
   if(error||!target?.user_id)return reply({error:'FORBIDDEN'},403);
   const token=Array.from(crypto.getRandomValues(new Uint8Array(32))).map(x=>x.toString(16).padStart(2,'0')).join('');
   const saved=await service.rpc('tkt_password_link_service',{p_action:'issue',p_data:{user_id:target.user_id,actor_id:identity.user.id,token_hash:await hash(token)}});
   if(saved.error)return reply({error:'RESET_UNAVAILABLE'},503);
   return reply({url:'https://x-spece.github.io/x-space-dashboard/captains/reset.html#'+token,phone:target.phone,expires_in:1800});
  }
  if(body.op==='redeem'){
   if(typeof body.token!=='string'||!/^([a-f0-9]{64})$/.test(body.token))return reply({error:'LINK_EXPIRED'},400);
   if(typeof body.password!=='string'||body.password.length<8||body.password.length>128)return reply({error:'INVALID_PASSWORD'},400);
   const token_hash=await hash(body.token);
   const {data:target,error}=await service.rpc('tkt_password_link_service',{p_action:'consume',p_data:{token_hash}});
   if(error||!target?.user_id)return reply({error:'LINK_EXPIRED'},400);
   const {error:updateError}=await service.auth.admin.updateUserById(target.user_id,{password:body.password});
   if(updateError)return reply({error:'RESET_UNAVAILABLE'},503);
   await service.rpc('tkt_password_link_service',{p_action:'complete',p_data:{token_hash}});
   return reply({ok:true});
  }
  return reply({error:'INVALID_ACTION'},400);
 }catch{return reply({error:'RESET_UNAVAILABLE'},503)}
});
