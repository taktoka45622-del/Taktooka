import { latLngToCell, gridDisk, gridDistance } from 'npm:h3-js@4.4.0';
export const cellAt = (lat: number, lng: number) => latLngToCell(lat, lng, 8);
export function zoneAt(zones: any[], lat: number, lng: number): string | null {
  for (const z of zones) {
    const ring = z.geometry.coordinates[0]; let inside = false;
    for (let i=0,j=ring.length-1;i<ring.length;j=i++) {
      const [x,y]=ring[i], [xx,yy]=ring[j];
      if ((y>lat)!==(yy>lat) && lng<(xx-x)*(lat-y)/(yy-y)+x) inside=!inside;
    }
    if(inside) return z.id;
  }
  return null;
}
export function ringCells(cell: string, k: number): string[] {
  if(k<=1) return gridDisk(cell,1);
  const prev=new Set(gridDisk(cell,k-1));return gridDisk(cell,k).filter(c=>!prev.has(c));
}
export function sortedEdges(edges: any[]): any[] {
 return [...edges].sort((a,b)=>a.eta_s-b.eta_s || Date.parse(a.created_at)-Date.parse(b.created_at) || a.ride_id.localeCompare(b.ride_id) || a.captain_id.localeCompare(b.captain_id));
}
export function matrixUrl(token: string, points: number[][], sourceCount: number) {
 const url=new URL('https://api.mapbox.com/directions-matrix/v1/mapbox/driving/'+points.map(p=>p.join(',')).join(';'));
 url.searchParams.set('access_token',token);url.searchParams.set('sources',Array.from({length:sourceCount},(_,i)=>i).join(';'));
 url.searchParams.set('destinations',Array.from({length:points.length-sourceCount},(_,i)=>i+sourceCount).join(';'));
 url.searchParams.set('annotations','duration');return url;
}
export async function matrix(token: string, caps: any[], pickup: number[], fetcher: typeof fetch=fetch): Promise<(number|null)[]> {
 const coords=caps.map(c=>[c.lng,c.lat]);coords.push([pickup[1],pickup[0]]);
 if(caps.length===1)coords.push([pickup[1],pickup[0]]);
 const response=await fetcher(matrixUrl(token,coords,caps.length),{signal:AbortSignal.timeout(4500)});
 if(!response.ok)throw Error('MAPBOX_MATRIX_'+response.status);
 const data=await response.json();
 if(data.code==='NoRoute')return caps.map(()=>null);
 if(data.code!=='Ok'||!Array.isArray(data.durations)||data.durations.length!==caps.length)throw Error('INVALID_MATRIX');
 return data.durations.map((row:any)=>Number.isFinite(row?.[0])&&row[0]>=0?Math.ceil(row[0]):null);
}
export async function dispatchCycle(snapshot: any, rpc: (op:string,data:any)=>Promise<any>, fetcher: typeof fetch=fetch) {
 const {lease_id,settings:s}=snapshot;
 let budget=4, used=false; const start=Date.now();const edges:any[]=[];const etas:any[]=[];
 if(s.last_matrix_at && Date.now()-Date.parse(s.last_matrix_at)<5000)budget=0;
 let error:string|null=null;
 try {
  for(const job of snapshot.jobs) {
   if(Date.now()-start>13000)break;
   const [lat,lng]=job.pickup, zone=zoneAt(s.zones,lat,lng);
   if(!zone||zone!==job.zone)continue;
   const origin=cellAt(lat,lng), tried=new Set(job.tried);
   const available=new Set((snapshot.available_cells||[]).filter((c:any)=>c.zone===zone).map((c:any)=>c.cell));
   if(!available.size)continue;
   const levels = [...new Set([1,...Array.from(available).map(c=>Math.max(1,gridDistance(origin,c as string)))])].sort((a,b)=>a-b);
   for(const k of levels) {
    if(Date.now()-start>13000)break;
    const cells=ringCells(origin,k).filter(c=>available.has(c));if(!cells.length)continue;
    const caps=(await rpc('candidates',{lease_id,ride_id:job.id,zone,cells})).filter((c:any)=>!tried.has(c.user_id));
    if(!caps.length)continue;
    const missing=caps.filter((c:any)=>!c.cached_at);
    for(let offset=0;offset<missing.length&&budget>0&&Date.now()-start<13000;offset+=24) {
     budget--; used=true;
     const batch=missing.slice(offset,offset+24), durations=await matrix(s.mapbox_token,batch,job.pickup,fetcher);
     const results=batch.map((c:any,i:number)=>({ride_id:job.id,captain_id:c.user_id,lat:c.lat,lng:c.lng,eta_s:durations[i]}));
     await rpc('cache',{lease_id,results});
     batch.forEach((c:any,i:number)=>{c.cached_at=new Date().toISOString();c.eta_s=durations[i];});
    }
    if(caps.some((c:any)=>!c.cached_at))break;
    const viable=caps.filter((c:any)=>c.eta_s!==null&&c.eta_s<=s.max_eta_s);
    if(viable.length) {
     edges.push(...viable.map((c:any)=>({ride_id:job.id,captain_id:c.user_id,eta_s:c.eta_s,gps_at:c.gps_at,created_at:job.created_at})));break;
    }
   }
  }
  await rpc('apply',{lease_id,edges:sortedEdges(edges)});
  for(const ride of snapshot.tracking) {
   if(budget<=0||Date.now()-start>13000)break;
   budget--;used=true;
   const [eta]=await matrix(s.mapbox_token,[ride],ride.pickup,fetcher);
   if(eta!==null)etas.push({ride_id:ride.id,eta_s:eta,gps_at:ride.location_at});
  }
 }catch(e){error=e instanceof Error?e.message:'DISPATCH_ERROR';}
 await rpc('finish',{lease_id,etas,error,matrix_used:used});
 return {offered_candidates:edges.length,error};
}
