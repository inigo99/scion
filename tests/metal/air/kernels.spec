# function: kind index:arg-kind[:location] ...
loops kernel 0:buffer:0 1:buffer:1 2:buffer:2 3:air.thread_position_in_grid
reduce kernel 0:buffer:0 1:buffer:1 2:buffer:2 3:air.thread_position_in_grid 4:air.thread_position_in_threadgroup 5:air.threadgroup_position_in_grid
structs kernel 0:buffer:0 1:buffer:1 2:air.thread_position_in_grid
simdk kernel 0:buffer:0 1:buffer:1 2:buffer:2 3:buffer:3 4:air.thread_position_in_grid 5:air.thread_index_in_simdgroup 6:air.threads_per_simdgroup
fc fc_mode uint mode 0
fc fc_scale float scale 3
fck kernel 0:buffer:0 1:air.thread_position_in_grid
