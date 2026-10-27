import {createClient} from 'npm:@supabase/supabase-js@2.95.3';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
const normalize=(v:unknown)=>{if(typeof v!=='string')return '';let s=v.trim().replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776)).replace(/[\s()-]/g,'');if(/^07\d{9}$/.test(s))s='+964'+s.slice(1);if(/^009647\d{9}$/.test(s))s='+'+s.slice(2);return /^\+9647\d{9}$/.test(s)?s:'';};
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 try{
  const body=await req.json();const phone=normalize(body.phone);
  if(!phone||typeof body.pin!=='string'||body.pin.length>128)return reply({error:'INVALID_ADMIN_LOGIN'},401);
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:staff,error:staffError}=await db.rpc('tkt_staff_login_lookup',{p_phone:phone});
  if(staffError)return reply({error:'ADMIN_LOGIN_UNAVAILABLE'},503);
  if(staff?.staff){
   if(!staff.allowed)return reply({error:staff.locked?'ADMIN_LOGIN_LOCKED':'INVALID_ADMIN_LOGIN'},staff.locked?429:401);
   const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
   const {data:login,error:loginError}=await client.auth.signInWithPassword({email:staff.email,password:body.pin});
   if(loginError||!login.session||login.user?.id!==staff.user_id)return reply({error:'INVALID_ADMIN_LOGIN'},401);
   const {data:access,error:accessError}=await client.rpc('tkt_dashboard_access');
   if(accessError||!access){await client.auth.signOut();return reply({error:'INVALID_ADMIN_LOGIN'},403);}
   await db.rpc('tkt_staff_login_success',{p_user:login.user.id});
   return reply({refresh_token:login.session.refresh_token});
  }
  const {data:credentials,error}=await db.rpc('tkt_admin_credentials',{p_phone:phone,p_pin:body.pin});
  if(error)return reply({error:'ADMIN_LOGIN_UNAVAILABLE'},503);
  if(!credentials?.ok)return reply({error:credentials?.locked?'ADMIN_LOGIN_LOCKED':'INVALID_ADMIN_LOGIN'},credentials?.locked?429:401);
  if(!credentials.user_id){
   // Native Auth creates the account; no raw auth.users inserts or client-controlled admin grant.
   const {error:createError}=await db.auth.admin.createUser({email:credentials.email,password:credentials.password,email_confirm:true});
   // A concurrent first login can create the same alias. Sign-in below safely resolves it using its random server password.
   if(createError&&!['email_exists','user_already_exists'].includes(createError.code??''))return reply({error:'ADMIN_LOGIN_UNAVAILABLE'},503);
  }
  const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:login,error:loginError}=await client.auth.signInWithPassword({email:credentials.email,password:credentials.password});
  if(loginError||!login.session||!login.user)return reply({error:'ADMIN_LOGIN_UNAVAILABLE'},503);
  const {error:bindError}=await db.rpc('tkt_admin_bind',{p_user:login.user.id});
  if(bindError){await client.auth.signOut();return reply({error:'INVALID_ADMIN_LOGIN'},403);}
  // Never return the internal password or service key. Only the user's normal refresh token reaches Flutter.
  return reply({refresh_token:login.session.refresh_token});
 }catch{return reply({error:'ADMIN_LOGIN_UNAVAILABLE'},503);}
});

