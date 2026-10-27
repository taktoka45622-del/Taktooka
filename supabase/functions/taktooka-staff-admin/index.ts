import {createClient} from 'npm:@supabase/supabase-js@2.95.3';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 try{
  const authorization=req.headers.get('authorization')||'';
  if(!authorization.startsWith('Bearer '))return reply({error:'AUTH_REQUIRED'},401);
  const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const service=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:identityError}=await service.auth.getUser(authorization.slice(7));
  if(identityError||!identity.user)return reply({error:'AUTH_REQUIRED'},401);
  const caller=createClient(url,key,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const body=await req.json();
  if(!['create','reset_password'].includes(body.op)||typeof body.password!=='string'||body.password.length<8||body.password.length>128)return reply({error:'INVALID_PASSWORD'},400);
  if(body.op==='create'){
   const {data:prepared,error:prepareError}=await caller.rpc('tkt_staff',{p_action:'prepare',p_data:{name:body.name,phone:body.phone,permissions:body.permissions}});
   if(prepareError||!prepared?.email)return reply({error:prepareError?.message||'FORBIDDEN'},403);
   const {data:created,error:createError}=await service.auth.admin.createUser({email:prepared.email,password:body.password,email_confirm:true});
   if(createError||!created.user)return reply({error:'STAFF_CREATE_FAILED'},409);
   const {error:attachError}=await caller.rpc('tkt_staff',{p_action:'attach',p_data:{user_id:created.user.id,name:body.name,phone:prepared.phone,permissions:body.permissions,active:body.active!==false}});
   if(attachError){await service.auth.admin.deleteUser(created.user.id);return reply({error:attachError.message},409);}
   return reply({ok:true,user_id:created.user.id});
  }
  const {data:target,error:targetError}=await caller.rpc('tkt_staff',{p_action:'reset_target',p_data:{user_id:body.user_id}});
  if(targetError||!target?.user_id)return reply({error:'FORBIDDEN'},403);
  const {error:updateError}=await service.auth.admin.updateUserById(target.user_id,{password:body.password});
  if(updateError)return reply({error:'PASSWORD_RESET_FAILED'},503);
  const {error:recordError}=await caller.rpc('tkt_staff',{p_action:'password_record',p_data:{user_id:target.user_id}});
  return reply({ok:true,...(recordError?{warning:'AUDIT_RETRY_REQUIRED'}:{})});
 }catch{return reply({error:'STAFF_OPERATION_FAILED'},503);}
});
