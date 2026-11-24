export const fib = (n: number): number => (n < 2 ? n : fib(n - 1) + fib(n - 2));
export interface Point { x: number; y: number }
export function dist(a: Point, b: Point) { return Math.hypot(a.x - b.x, a.y - b.y); }
