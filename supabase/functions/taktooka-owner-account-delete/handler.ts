const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
export function createHandler(service){
 return async request=>{
  if(request.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(request.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
  try{
   const bearer=request.headers.get('authorization')||'';if(!bearer.startsWith('Bearer '))return reply({error:'AUTH_REQUIRED'},401);
   const {data:identity,error:authError}=await service.auth.getUser(bearer.slice(7));if(authError||!identity?.user)return reply({error:'AUTH_REQUIRED'},401);
   let body;try{body=await request.json();}catch{return reply({error:'INVALID_REQUEST'},400);}
   if(body.confirm!=='DELETE_ACCOUNT'||!['user','exchange'].includes(body.kind)||!/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/.test(body.id||'')||typeof body.fingerprint!=='string'||body.fingerprint.length!==64)return reply({error:'CONFIRM_REQUIRED'},400);
   const actor=identity.user.id;
   const call=async(action,data)=>{const r=await service.rpc('tkt_admin_account_delete',{p_action:action,p_data:data,p_actor:actor});if(r.error)throw new Error(r.error.message);return r.data;};
   const job=await call('prepare',body);
   if(job.status==='completed')return reply({ok:true,self:job.self===true});
   for(const file of job.files||[]){
    if(!job.user_id||!['profile-photos','captain-documents','tkt-line-documents'].includes(file.bucket)||typeof file.name!=='string'||file.name.split('/')[0]!==job.user_id)throw new Error('INVALID_STORAGE_TARGET');
   }
   for(const bucket of ['profile-photos','captain-documents','tkt-line-documents']){
    const names=(job.files||[]).filter(f=>f.bucket===bucket).map(f=>f.name);for(let i=0;i<names.length;i+=100){const r=await service.storage.from(bucket).remove(names.slice(i,i+100));if(r.error)throw new Error('STORAGE_FAILED');}
   }
   await call('purge',{job_id:job.id});
   if(job.user_id){
    const {data:authTarget,error:targetError}=await service.auth.admin.getUserById(job.user_id);
    if(targetError&&targetError.status!==404)throw new Error('AUTH_DELETE_FAILED');
    if(authTarget?.user&&!authTarget.user.deleted_at){
     const checks=await Promise.all(['x_profiles','x_admins'].map(table=>service.from(table).select('user_id').eq('user_id',job.user_id).limit(1)));
     if(checks.some(r=>r.error))throw new Error('AUTH_DELETE_FAILED');
     if(checks.every(r=>!r.data?.length)&&/@(accounts\.taktooka\.invalid|taktooka\.internal)$/i.test(authTarget.user.email||'')){
      const result=await service.auth.admin.deleteUser(job.user_id,true);if(result.error)throw new Error('AUTH_DELETE_FAILED');
     }
    }
   }
   await call('finish',{job_id:job.id});return reply({ok:true,self:job.self===true});
  }catch(e){const error=String(e?.message||'DELETE_UNAVAILABLE');const known=['OWNER_REQUIRED','LAST_OWNER','ACTIVE_RIDE','ACTIVE_LINE','SETTLE_BALANCE','SETTLE_EXCHANGE','ACCOUNT_CHANGED','ACCOUNT_DELETED','ACCOUNT_NOT_FOUND','STORAGE_FAILED','AUTH_DELETE_FAILED','INVALID_STORAGE_TARGET'];const code=known.find(c=>error.includes(c))||'DELETE_UNAVAILABLE';return reply({error:code},code==='OWNER_REQUIRED'?403:code==='DELETE_UNAVAILABLE'?503:409);}
 };
}
