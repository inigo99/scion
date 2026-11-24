; simdgroup_matrix test (written in IR: a <64 x float> can't cross C's ABI). One SIMD group of 32 threads.
; out[0..63]    = A*B + 1               (load, init_filled, multiply_accumulate, store)
; out[64..127]  = A transposed          (store with transpose)
; out[128..383] = 16x16 with A*B at origin (x=8, y=8), stride 16
; e[2*lane..]   = this thread's two elements of A (shufflevector, as MLX's thread_elements())
target triple = "x86_64-unknown-linux"
declare <64 x float> @air.simdgroup_matrix_8x8_load.v64f32.p1f32(ptr addrspace(1), i64, <2 x i64>, i1)
declare void @air.simdgroup_matrix_8x8_store.v64f32.p1f32(<64 x float>, ptr addrspace(1), i64, <2 x i64>, i1)
declare <64 x float> @air.simdgroup_matrix_8x8_multiply_accumulate.v64f32.v64f32.v64f32.v64f32(<64 x float>, <64 x float>, <64 x float>)
declare <64 x float> @air.simdgroup_matrix_8x8_init_filled.v64f32.f32(float)

define void @mma(ptr addrspace(1) %A, ptr addrspace(1) %B, ptr addrspace(1) %out, ptr addrspace(1) %e, i32 %lane) {
  %a = call <64 x float> @air.simdgroup_matrix_8x8_load.v64f32.p1f32(ptr addrspace(1) %A, i64 8, <2 x i64> zeroinitializer, i1 false)
  %b = call <64 x float> @air.simdgroup_matrix_8x8_load.v64f32.p1f32(ptr addrspace(1) %B, i64 8, <2 x i64> zeroinitializer, i1 false)
  %c = call <64 x float> @air.simdgroup_matrix_8x8_init_filled.v64f32.f32(float 1.0)
  %d = call <64 x float> @air.simdgroup_matrix_8x8_multiply_accumulate.v64f32.v64f32.v64f32.v64f32(<64 x float> %a, <64 x float> %b, <64 x float> %c)
  call void @air.simdgroup_matrix_8x8_store.v64f32.p1f32(<64 x float> %d, ptr addrspace(1) %out, i64 8, <2 x i64> zeroinitializer, i1 false)
  %o2 = getelementptr float, ptr addrspace(1) %out, i64 64
  call void @air.simdgroup_matrix_8x8_store.v64f32.p1f32(<64 x float> %a, ptr addrspace(1) %o2, i64 8, <2 x i64> zeroinitializer, i1 true)
  %d2 = call <64 x float> @air.simdgroup_matrix_8x8_multiply_accumulate.v64f32.v64f32.v64f32.v64f32(<64 x float> %a, <64 x float> %b, <64 x float> zeroinitializer)
  %o3 = getelementptr float, ptr addrspace(1) %out, i64 128
  call void @air.simdgroup_matrix_8x8_store.v64f32.p1f32(<64 x float> %d2, ptr addrspace(1) %o3, i64 16, <2 x i64> <i64 8, i64 8>, i1 false)
  %te = shufflevector <64 x float> %a, <64 x float> poison, <2 x i32> <i32 0, i32 1>
  %idx = zext i32 %lane to i64
  %i2 = shl i64 %idx, 1
  %ep = getelementptr float, ptr addrspace(1) %e, i64 %i2
  store <2 x float> %te, ptr addrspace(1) %ep, align 4
  ret void
}
