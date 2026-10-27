import {createClient} from 'npm:@supabase/supabase-js@2.95.3';
import {normalize,readPlaces,rankPlaces,matchQuality,localBounds,queryPrefix} from './places.ts';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply = (data: unknown,status=200) => new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
const calls = new Map<string,number[]>();
const cache = new Map<string,{at:number,results:any[]}>();
Deno.serve(async (req: Request) => {
 if (req.method === 'OPTIONS') return new Response('ok',{headers:cors});
 if (req.method !== 'POST') return reply({error:'METHOD_NOT_ALLOWED'},405);
 try {
  const db = createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const token = (req.headers.get('Authorization')??'').replace(/^Bearer\s+/i,'');
  const {data:{user},error} = await db.auth.getUser(token);
  if (error || !user) return reply({error:'AUTH_REQUIRED'},401);
  const {data:profile} = await db.from('tkt_profiles').select('blocked').eq('user_id',user.id).maybeSingle();
  if (!profile || profile.blocked) return reply({error:'PROFILE_REQUIRED'},403);
  const body = await req.json(), query = typeof body.query === 'string' ? body.query.trim() : '', point = body.point;
  if (query.length<2 || query.length>200 || !Array.isArray(point) || point.length!==2 || !point.every(Number.isFinite) || point[0]<29 || point[0]>38 || point[1]<38 || point[1]>49) return reply({error:'INVALID_SEARCH'},400);
  const now = Date.now(), recent = (calls.get(user.id)??[]).filter(n=>n>now-60000);
  if (recent.length>=45) return reply({error:'RATE_LIMIT'},429);
  calls.set(user.id,[...recent,now]);
  if (calls.size>2000) for (const [id,times] of calls) if (times.at(-1)!<now-60000) calls.delete(id);
  const key = `${normalize(query)}|${point[0].toFixed(2)}|${point[1].toFixed(2)}`, hit = cache.get(key);
  if (hit && now-hit.at<300000) return reply({results:hit.results});
  const {data:config,error:configError} = await db.rpc('tkt_route_config');
  if (configError || !config?.mapbox_token) return reply({error:'SEARCH_UNAVAILABLE'},503);
  const mapbox = new URL('https://api.mapbox.com/search/geocode/v6/forward');
  mapbox.search = new URLSearchParams({q:query,country:'iq',language:'ar',limit:'10',autocomplete:'true',permanent:'true',access_token:config.mapbox_token,proximity:`${point[1]},${point[0]}`}).toString();
  const photon = new URL('/api/',Deno.env.get('PHOTON_URL') || 'https://photon.komoot.io');
  photon.search = new URLSearchParams({q:query,lat:String(point[0]),lon:String(point[1]),limit:'10',bbox:'38,29,49,38'}).toString();
  let succeeded = false;
  const get = async (url: URL,provider: string) => {
   try {const r = await fetch(url,{headers:{'Accept-Language':'ar'},signal:AbortSignal.timeout(3000)}); if (!r.ok) return []; const data = await r.json(); if (!Array.isArray(data?.features)) return []; succeeded=true;return readPlaces(data,provider);} catch {return [];}
  };
  const groups = await Promise.all([get(mapbox,'mapbox'),get(photon,'photon')]);
  if (!succeeded) return reply({error:'SEARCH_UNAVAILABLE'},503);
  const rows = groups.flat();
  const prefix=queryPrefix(query);
  if(prefix && !rows.some(row=>matchQuality(row,query)>=.7)) {
   const local=new URL(photon);
   local.searchParams.set('q',prefix);
   local.searchParams.set('bbox',localBounds(point));
   local.searchParams.set('limit','20');
   rows.push(...await get(local,'photon'));
  }
  const results = rankPlaces(rows,query,point);
  if (results.length) {if(cache.size>=250) cache.delete(cache.keys().next().value!);cache.set(key,{at:now,results});}
  return reply({results});
 } catch {return reply({error:'SEARCH_UNAVAILABLE'},503);}
});
