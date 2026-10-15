///|
// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
async test "close interrupts wait_pid" {
  // On Linux, `wait_pid` waits for a pidfd, which is interrupted by `close`.
  // MacOS waits for the PID via kqueue instead, and Windows is not supported yet.
  guard @event_loop.platform is Linux else {  }
  let test_prog = sleep_prog.wait()
  let pid = @process.spawn_orphan(test_prog, ["500"])
  let context = "close interrupts wait_pid"
  let proc = @event_loop.Process::from_pid(pid, context~)
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @async.sleep(50)
      proc.close()
    }
    // If `close` runs before `wait_pid` blocks, `wait_pid` fails with `EBADF` as well
    let raised = @async.with_timeout_opt(1000, () => {
      try proc.wait_pid(context~) catch {
        @os_error.OSError(errno, ..) if errno == @os_error.errno_EBADF => true
        err => raise err
      } noraise {
        _ => false
      }
    })
    guard raised is Some(true) else {
      fail("wait_pid not interrupted by close")
    }
  }
  // reap the process
  ignore(@process.wait_pid(pid))
}
