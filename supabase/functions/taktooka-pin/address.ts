function clean(value: unknown): string {return typeof value === 'string' ? value.trim().slice(0,100) : '';}
function meters(point: number[], xy: unknown): number {
 if (!Array.isArray(xy) || xy.length !== 2 || !xy.every(Number.isFinite)) return Infinity;
 return Math.hypot((xy[1]-point[0])*111320,(xy[0]-point[1])*111320*Math.cos(point[0]*Math.PI/180));
}
export function addressParts(data: any, road = '', nearby: any = null, point?: number[], local: any = null) {
 const features = Array.isArray(data?.features) ? data.features : [];
 const props = features.find((f: any) => f?.properties?.feature_type === 'street')?.properties ?? features[0]?.properties ?? {};
 const context = props.context ?? {};
 const value = (type: string) => {
  const feature = features.find((f: any) => f?.properties?.feature_type === type)?.properties;
  const item = context[type];
  return clean(item?.name_preferred || item?.name || feature?.name_preferred || feature?.name);
 };
 const localFeatures = (Array.isArray(local?.features) ? local.features : [])
  .filter((f: any) => f?.properties?.countrycode?.toLowerCase() === 'iq')
  .map((f: any) => ({props:f.properties, distance:point ? meters(point,f.geometry?.coordinates) : Infinity}))
  .filter((f: any) => f.distance <= 1000).sort((a: any,b: any) => a.distance-b.distance);
 const localAddress = localFeatures[0]?.props ?? {};
 const province = value('region') || clean(localAddress.state) || value('place');
 const district = clean(localAddress.district) || value('locality') || value('district') || clean(localAddress.city);
 const area = [...new Set([district,value('neighborhood')].filter(v=>v && v!==province))].join('، ');
 const candidates = (Array.isArray(nearby?.features) ? nearby.features : []).map((f: any) => ({
  name: clean(f?.properties?.name_ar || f?.properties?.name),
  distance: f?.properties?.tilequery?.distance,
  layer: f?.properties?.tilequery?.layer,
 })).filter((p: any) => p.name && Number.isFinite(p.distance) && p.distance >= 0 && p.distance <= 500 && ['road','poi_label'].includes(p.layer));
 for (const f of localFeatures) {
  const name=clean(f.props.name), kind=f.props.osm_key;
  if (name && f.distance<=500 && !['place','boundary','highway'].includes(kind)) candidates.push({name,distance:f.distance,layer:'poi_label'});
 }
 candidates.sort((a: any,b: any) => a.distance-b.distance);
 const streetFeature = features.find((f: any) => f?.properties?.feature_type === 'street');
 const closeStreet = point && meters(point,streetFeature?.geometry?.coordinates) <= 25;
 const tileStreet = candidates.find((p: any) => p.layer==='road' && p.distance<=25);
 const street = clean(road) || (closeStreet ? clean(streetFeature?.properties?.name_preferred || streetFeature?.properties?.name) : '') || tileStreet?.name || '';
 const landmarkCandidate = candidates.find((p: any) => p.layer==='poi_label' && p.name!==street);
 const landmark = landmarkCandidate?.name || '';
 const closest = candidates.find((p: any) => p.name!==province && p.name!==district);
 const parts=[...new Set([province,area,street].filter(Boolean))];
 const detail=street ? (landmarkCandidate?.distance<=120 ? landmark : '') : closest?.name || '';
 if (detail && !parts.includes(detail) && !area.split('، ').includes(detail)) parts.push(`قرب ${detail}`);
 const name=parts.join('، ').slice(0,240);
 return {province,area,street,landmark,name,detail,detail_distance_m:street ? landmarkCandidate?.distance ?? null : closest?.distance ?? null,address_complete:Boolean(province && area && (street || detail))};
}
export function readAreaName(data: any): string {return addressParts(data).name;}
