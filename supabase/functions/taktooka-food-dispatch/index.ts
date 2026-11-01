import {createClient} from 'npm:@supabase/supabase-js@2.95.3';
import {dispatchCycle} from './core.ts';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const rpc=async(op:string,data:any={})=>{const {data:result,error}=await db.rpc('tkt_food_dispatch_worker',{p_action:op,p_data:data});if(error)throw Error(error.message);return result;};
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return Response.json({error:'METHOD_NOT_ALLOWED'},{status:405});
 try {
  const body=await req.json();
  const snapshot=await rpc('lease',{worker_token:body.worker_token});
  if(snapshot.busy)return Response.json({busy:true});
  return Response.json(await dispatchCycle(snapshot,rpc));
 }catch(e){const error=e instanceof Error?e.message:'SERVICE_UNAVAILABLE';return Response.json({error},{status:error==='AUTH_REQUIRED'?401:503});}
});
