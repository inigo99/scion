import { fib, dist } from "./util/math";
const msg: string = `fib(20) = ${fib(20)}, dist = ${dist({ x: 0, y: 0 }, { x: 3, y: 4 })}`;
console.log("scion + esbuild:", msg);
