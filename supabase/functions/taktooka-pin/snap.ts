export const maxPinSnapMeters = 150;
export function readSnap(data: any, point: number[]): {point: number[]; name: string} {
 const location = data?.waypoints?.[0]?.location;
 if (data?.code !== 'Ok' || !Array.isArray(location) || location.length !== 2 || !location.every((n: unknown) => typeof n === 'number' && Number.isFinite(n))) throw new Error('NO_NEARBY_ROAD');
 const rad = Math.PI / 180;
 const dlat = (location[1]-point[0])*rad, dlng = (location[0]-point[1])*rad;
 const a = Math.sin(dlat/2)**2 + Math.cos(point[0]*rad)*Math.cos(location[1]*rad)*Math.sin(dlng/2)**2;
 const distance = 6371000*2*Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
 if (distance > maxPinSnapMeters) throw new Error('NO_NEARBY_ROAD');
 const routes = data.routes;
 if (!Array.isArray(routes) || !routes.length) throw new Error('NO_NEARBY_ROAD');
 for (const route of routes) {
  const notifications = [...(route.notifications ?? []), ...(route.legs ?? []).flatMap((leg: any) => [...(leg.notifications ?? []), ...(leg.steps ?? []).flatMap((step: any) => step.notifications ?? [])])];
  if (notifications.some((n: any) => n.type === 'violation')) throw new Error('NO_NEARBY_ROAD');
 }
 return {point: [location[1], location[0]], name: typeof data.waypoints[0].name === 'string' ? data.waypoints[0].name.slice(0, 160) : ''};
}
