export function normalize(text: string): string {
 return text.toLowerCase().replace(/[\u064B-\u065F\u0670ـ]/g,'').replace(/[أإآٱ]/g,'ا').replace(/ى/g,'ي').replace(/ة/g,'ه').replace(/\s+/g,' ').trim();
}
export function readPlaces(data: any, provider: string) {
 return (Array.isArray(data?.features) ? data.features : []).flatMap((f: any) => {
  const p = f?.properties ?? {}, xy = f?.geometry?.coordinates;
  if (!Array.isArray(xy) || xy.length !== 2 || !xy.every(Number.isFinite) || xy[1]<29 || xy[1]>38 || xy[0]<38 || xy[0]>49) return [];
  if (provider === 'photon' && p.countrycode?.toLowerCase() !== 'iq') return [];
  const c = p.context ?? {};
  const title = p.name_preferred || p.name || p.street || p.city;
  if (typeof title !== 'string' || !title.trim()) return [];
  const parts = provider === 'photon' ? [p.state,p.city,p.district,p.street,title] : [c.region?.name,c.place?.name,c.locality?.name,c.neighborhood?.name,c.street?.name,title];
  const label = [...new Set(parts.filter((s: any) => typeof s === 'string' && s.trim()).map((s: string) => s.trim()))].join('، ').slice(0,240);
  return [{label,point:[xy[1],xy[0]],title:title.trim(),provider}];
 });
}
function edits(a: string,b: string): number {
 let previous = Array.from({length:b.length+1},(_,i)=>i);
 for (let i=1;i<=a.length;i++) {
  const next=[i];
  for(let j=1;j<=b.length;j++) next[j]=Math.min(next[j-1]+1,previous[j]+1,previous[j-1]+(a[i-1]===b[j-1]?0:1));
  previous=next;
 }
 return previous[b.length];
}
export function matchQuality(row: any, query: string): number {
 const words=normalize(query).split(' ').filter(Boolean);
 const candidates=normalize(row.label).split(/[\s،,]+/).filter(Boolean);
 const values=words.map(word=>Math.max(0,...candidates.map((candidate: string)=> {
  if(candidate===word) return 1;
  if(word.length>=2 && candidate.startsWith(word)) return .9;
  if(word.length>=4 && Math.abs(candidate.length-word.length)<=1 && edits(candidate,word)<=1) return .85;
  if(word.length>=7 && Math.abs(candidate.length-word.length)<=2 && edits(candidate,word)<=2) return .7;
  return 0;
 })));
 return values.length && values.every(value=>value>0) ? values.reduce((a,b)=>a+b,0)/values.length : 0;
}
export function localBounds(origin: number[]): string {
 const lat=25000/111320,lon=lat/Math.cos(origin[0]*Math.PI/180);
 return `${Math.max(38,origin[1]-lon)},${Math.max(29,origin[0]-lat)},${Math.min(49,origin[1]+lon)},${Math.min(38,origin[0]+lat)}`;
}
export function queryPrefix(query: string): string | null {
 const words=query.trim().split(/\s+/),last=words.at(-1)!;
 if(last.length<5) return null;
 words[words.length-1]=last.slice(0,-2);
 return words.join(' ');
}
export function rankPlaces(rows: any[], query: string, origin: number[]) {
 const q=normalize(query), unique: any[]=[];
 const distance=(p: number[])=>Math.hypot((p[0]-origin[0])*111320,(p[1]-origin[1])*111320*Math.cos(origin[0]*Math.PI/180));
 const quality=(r: any)=>matchQuality(r,query);
 const matched=rows.filter(r=>quality(r)>=.7);
 const candidates=matched.length ? matched : rows;
 const hasLocalMatch=matched.some(r=>distance(r.point)<=25000);
 const score=(r: any)=>{
  const title=normalize(r.title);
  return quality(r)*100 + (title===q ? 35 : title.startsWith(q) ? 20 : 0) - Math.min(distance(r.point)/3000,55);
 };
 candidates.sort((a,b)=>{
  if(hasLocalMatch) {
   const localA=distance(a.point)<=25000, localB=distance(b.point)<=25000;
   if(localA!==localB) return localA ? -1 : 1;
  }
  return score(b)-score(a);
 });
 for(const row of candidates) {
  if(unique.some(r=>normalize(r.title)===normalize(row.title) && Math.hypot(r.point[0]-row.point[0],r.point[1]-row.point[1])<.001)) continue;
  unique.push(row);
 }
 return unique.slice(0,10);
}
