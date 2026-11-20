export interface CatalogCourse {
  id: string; name: string; shortName?: string; courseRating?: number; slopeRating?: number;
  holes: { number: number; par: number; handicap: number; yardage: number }[];
}
let cache: CatalogCourse[] | null = null;

export async function loadCourses(): Promise<CatalogCourse[]> {
  if (cache) return cache;
  try { cache = await (await fetch("/courses.json")).json(); } catch { cache = []; }
  return cache!;
}
export function findCourse(list: CatalogCourse[], name: string): CatalogCourse | undefined {
  const w = name.trim().toLowerCase();
  return list.find((c) => c.name.toLowerCase() === w || c.shortName?.toLowerCase() === w);
}
