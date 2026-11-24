/* Metal compute from a macOS program (like Apple's "MetalAdder" sample). Loads add.metallib (compiled by Apple's tools,
 * from Indium's test suite), adds two arrays on the GPU and checks the result. Prints "METAL COMPUTE OK". */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { printf("METAL: no device\n"); return 1; }
        printf("GPU: %s\n", device.name.UTF8String);
        NSString *dir = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        NSError *error = nil;
        id<MTLLibrary> lib = [device newLibraryWithFile:[dir stringByAppendingPathComponent:@"add.metallib"] error:&error];
        if (!lib) { printf("METAL: %s\n", error.localizedDescription.UTF8String); return 1; }
        printf("functions: %s\n", [[lib.functionNames componentsJoinedByString:@","] UTF8String]);
        id<MTLFunction> fn = [lib newFunctionWithName:@"add_arrays"];
        id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:fn error:&error];
        if (!pso) { printf("METAL: %s\n", error.localizedDescription.UTF8String); return 1; }

        const NSUInteger n = 1 << 20;
        id<MTLBuffer> a = [device newBufferWithLength:n * sizeof(float) options:MTLResourceStorageModeShared];
        id<MTLBuffer> b = [device newBufferWithLength:n * sizeof(float) options:MTLResourceStorageModeShared];
        id<MTLBuffer> r = [device newBufferWithLength:n * sizeof(float) options:MTLResourceStorageModeShared];
        float *pa = a.contents, *pb = b.contents, *pr = r.contents;
        for (NSUInteger i = 0; i < n; i++) { pa[i] = (float)i * 0.5f; pb[i] = (float)(n - i); }

        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        __block BOOL completed = NO;
        [cb addCompletedHandler:^(id<MTLCommandBuffer> c) { completed = YES; }];
        id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
        [enc setComputePipelineState:pso];
        [enc setBuffer:a offset:0 atIndex:0];
        [enc setBuffer:b offset:0 atIndex:1];
        [enc setBuffer:r offset:0 atIndex:2];
        NSUInteger tg = pso.maxTotalThreadsPerThreadgroup; if (tg > n) tg = n;
        [enc dispatchThreads:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(tg, 1, 1)];
        [enc endEncoding];
        NSDate *t0 = [NSDate date];
        [cb commit];
        [cb waitUntilCompleted];
        double ms = -[t0 timeIntervalSinceNow] * 1000;
        for (int i = 0; i < 100 && !completed; i++) [NSThread sleepForTimeInterval:0.01];

        NSUInteger bad = 0;
        for (NSUInteger i = 0; i < n; i++) if (pr[i] != pa[i] + pb[i]) bad++;
        printf("%lu sums on the GPU (%.1f ms), errors: %lu, completedHandler: %s, status: %lu\n",
               (unsigned long)n, ms, (unsigned long)bad, completed ? "si" : "no", (unsigned long)cb.status);
        printf(bad == 0 && completed && cb.status == MTLCommandBufferStatusCompleted ? "METAL COMPUTE OK\n" : "METAL COMPUTE FAIL\n");
        return bad ? 1 : 0;
    }
}
