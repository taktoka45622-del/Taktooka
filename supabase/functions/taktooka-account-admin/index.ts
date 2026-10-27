import { createClient } from 'npm:@supabase/supabase-js@2.95.3';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply = (data:unknown,status=200) => new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async (request:Request) => {
 if(request.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(request.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 try {
  const authorization=request.headers.get('authorization')||'';
  if(!authorization.startsWith('Bearer '))return reply({error:'AUTH_REQUIRED'},401);
  const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const service=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:authError}=await service.auth.getUser(authorization.slice(7));
  if(authError||!identity.user)return reply({error:'AUTH_REQUIRED'},401);
  const caller=createClient(url,key,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const body=await request.json();
  if(body.op!=='reset_password'||typeof body.password!=='string'||body.password.length<8||body.password.length>128)return reply({error:'INVALID_PASSWORD'},400);
  const {data:target,error}=await caller.rpc('tkt_manage',{p_action:'reset_target',p_data:{user_id:body.user_id,phone:body.phone}});
  if(error||!target?.user_id)return reply({error:'FORBIDDEN'},403);
  const {error:updateError}=await service.auth.admin.updateUserById(target.user_id,{password:body.password});
  if(updateError)return reply({error:'RESET_UNAVAILABLE'},503);
  const {error:auditError}=await caller.rpc('tkt_manage',{p_action:'password_reset_record',p_data:{user_id:target.user_id,phone:target.phone}});
  if(auditError)return reply({ok:true,warning:'AUDIT_RETRY_REQUIRED'});
  return reply({ok:true});
 }catch{return reply({error:'RESET_UNAVAILABLE'},503)}
});
