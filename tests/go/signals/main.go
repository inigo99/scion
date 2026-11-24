// Signal test for scion: nil-pointer panics (SIGSEGV -> recover)
// and asynchronous preemption (SIGURG): runtime.GC() with a goroutine in a tight loop.
package main

import (
	"fmt"
	"os"
	"runtime"
	"sync"
	"time"
)

type node struct{ v int }

func nilDeref() (msg string) {
	defer func() {
		if r := recover(); r != nil {
			msg = fmt.Sprint(r)
		}
	}()
	var p *node
	return fmt.Sprint(p.v)
}

func index(i int) (msg string) {
	defer func() {
		if r := recover(); r != nil {
			msg = fmt.Sprint(r)
		}
	}()
	a := []int{1, 2, 3}
	return fmt.Sprint(a[i])
}

func main() {
	fmt.Println("nil:", nilDeref())
	fmt.Println("index:", index(len(os.Args)+5))
	runtime.GOMAXPROCS(2)
	var stop bool
	go func() {
		x := 0
		for !stop { // loop without calls: only asynchronous preemption can stop it
			x++
		}
	}()
	time.Sleep(20 * time.Millisecond)
	start := time.Now()
	runtime.GC()
	fmt.Println("GC with a tight loop: ok", time.Since(start) < 5*time.Second)
	var wg sync.WaitGroup
	sum := make([]int, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) { defer wg.Done(); for j := 0; j < 1000000; j++ { sum[i] += j % 7 } }(i)
	}
	wg.Wait()
	fmt.Println("goroutines:", sum[0], sum[7])
	stop = true
}
