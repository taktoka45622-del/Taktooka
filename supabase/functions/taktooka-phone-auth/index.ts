import {createClient} from 'npm:@supabase/supabase-js@2.95.3';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
export const normalize=(v:unknown)=>{if(typeof v!=='string')return '';let s=v.trim().replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776)).replace(/[\s()-]/g,'');if(/^07\d{9}$/.test(s))s='+964'+s.slice(1);if(/^9647\d{9}$/.test(s))s='+'+s;if(/^009647\d{9}$/.test(s))s='+'+s.slice(2);return /^\+9647\d{9}$/.test(s)?s:''};
const hash=async(v:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v)))).map(v=>v.toString(16).padStart(2,'0')).join('');
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 try{
 const body=await req.json(),phone=normalize(body.phone),op=body.op;
 const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 if(op==='recovery_read'||op==='recovery_send'){
  if(typeof body.token!=='string'||body.token.length!==64||typeof body.thread_id!=='string')return reply({error:'FORBIDDEN'},403);
  const {data:t}=await db.from('tkt_recovery_threads').select('id,created_at').eq('id',body.thread_id).eq('token_hash',await hash(body.token)).maybeSingle();
  if(!t||Date.now()-Date.parse(t.created_at)>7*86400000)return reply({error:'FORBIDDEN'},403);
  if(op==='recovery_send'){
   if(typeof body.body!=='string'||!body.body.trim()||body.body.length>2000)return reply({error:'INVALID_MESSAGE'},400);
   const {count}=await db.from('tkt_recovery_messages').select('id',{count:'exact',head:true}).eq('thread_id',t.id).eq('is_admin',false).gte('created_at',new Date(Date.now()-60000).toISOString());
   if((count??0)>=20)return reply({error:'RATE_LIMIT'},429);
   const {error}=await db.from('tkt_recovery_messages').insert({id:body.message_id,thread_id:t.id,body:body.body.trim(),is_admin:false});
   if(error&&error.code!=='23505')return reply({error:'SUPPORT_UNAVAILABLE'},503);
  }
  const {data,error}=await db.from('tkt_recovery_messages').select('id,body,is_admin,created_at').eq('thread_id',t.id).order('created_at',{ascending:false}).limit(200);
  return error?reply({error:'SUPPORT_UNAVAILABLE'},503):reply({messages:(data??[]).reverse()});
 }
 if(!phone||!['probe','register','login','recovery_create'].includes(op))return reply({error:'INVALID_PHONE'},400);
 if(['login','register'].includes(op)){if(typeof body.password!=='string'||body.password.length<(op==='register'?8:1)||body.password.length>128)return reply({error:'INVALID_PASSWORD'},400);}
 const {data:gate,error}=await db.rpc('tkt_phone_gate',{p_phone:phone,p_op:op==='login'?'attempt':op==='recovery_create'?'recovery':'probe'});
 if(error)return reply({error:'LOGIN_UNAVAILABLE'},503);
 if(gate.limited)return reply({error:'RATE_LIMIT'},429);
 if(op==='probe')return reply({exists:gate.exists,locked:gate.locked,ambiguous:gate.ambiguous===true});
 if(op==='recovery_create'){
  const token=crypto.randomUUID().replaceAll('-','')+crypto.randomUUID().replaceAll('-','');
  const {data,error}=await db.from('tkt_recovery_threads').insert({phone,name:String(body.name??'').trim().slice(0,80),token_hash:await hash(token)}).select('id').single();
  return error?reply({error:'SUPPORT_UNAVAILABLE'},503):reply({thread_id:data.id,token});
 }
 if(gate.ambiguous)return reply({error:'CONTACT_SUPPORT',remaining:0},409);
 if(gate.locked)return reply({error:'LOGIN_LOCKED',remaining:0},429);
 let loginEmail=gate.email;
 if(op==='register'){
  if(gate.exists)return reply({error:'ACCOUNT_EXISTS'},409);
  const name=String(body.name??'').trim();if(!name||name.length>80)return reply({error:'INVALID_NAME'},400);
  const {data,error}=await db.auth.admin.createUser({email:`phone-${crypto.randomUUID()}@accounts.taktooka.invalid`,password:body.password,email_confirm:true,user_metadata:{name,phone}});
  if(error||!data.user)return reply({error:['phone_exists','user_already_exists'].includes(error?.code??'')?'ACCOUNT_EXISTS':'REGISTER_UNAVAILABLE'},409);
  loginEmail=data.user.email;
  const {error:profileError}=await db.from('tkt_profiles').upsert({user_id:data.user.id,name,phone},{onConflict:'user_id'});
  if(profileError)return reply({error:'REGISTER_UNAVAILABLE'},503);
 }
 const login=loginEmail?{email:loginEmail,password:body.password}:{phone:gate.auth_phone||phone,password:body.password};
 const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error:loginError}=await client.auth.signInWithPassword(login);
 if(loginError||!data.session)return reply({error:'WRONG_PASSWORD',remaining:gate.remaining??2},401);
 const {data:profile}=await db.from('tkt_profiles').select('blocked').eq('user_id',data.user.id).maybeSingle();
 if(profile?.blocked)return reply({error:'ACCOUNT_BLOCKED'},403);
 await db.rpc('tkt_phone_gate',{p_phone:phone,p_op:'success'});
 return reply({refresh_token:data.session.refresh_token});
 }catch{return reply({error:'LOGIN_UNAVAILABLE'},503)}
});
