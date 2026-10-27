export function nearbyLabel(data: any): string {
 const features = Array.isArray(data?.features) ? data.features : [];
 const candidates = features.map((f: any) => {
  const p = f?.properties ?? {};
  const distance = p.tilequery?.distance;
  const layer = p.tilequery?.layer;
  const name = p.name_ar || p.name;
  return {distance,layer,name};
 }).filter((p: any) => typeof p.name === 'string' && p.name.trim() &&
   typeof p.distance === 'number' && Number.isFinite(p.distance) && p.distance >= 0);
 const road = candidates.filter((p: any) => p.layer === 'road' && p.distance <= 25)
   .sort((a: any,b: any) => a.distance-b.distance)[0];
 if (road) return road.name.trim().slice(0,160);
 const poi = candidates.filter((p: any) => p.layer === 'poi_label' && p.distance <= 60)
   .sort((a: any,b: any) => a.distance-b.distance)[0];
 return poi ? `قرب ${poi.name.trim()}`.slice(0,160) : '';
}
