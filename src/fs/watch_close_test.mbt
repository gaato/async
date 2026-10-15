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
async test "close interrupts Watcher::wait (kqueue)" {
  // The kqueue backend waits on the kqueue fd in the waiting task itself,
  // so `close` makes `wait` fail with `EBADF`.
  // The inotify (Linux) and Windows backends are not covered here.
  guard @event_loop.platform is MacOS else {  }
  let path = "watch_close_test_dir"
  @fs.mkdir(path)
  defer @fs.rmdir(path, recursive=true)
  let watcher = @fs.Watcher(path)
  defer watcher.close()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @async.sleep(50)
      watcher.close()
    }
    let raised = @async.with_timeout_opt(1000, () => {
      try watcher.wait() catch {
        @os_error.OSError(errno, ..) if errno == @os_error.errno_EBADF => true
        err => raise err
      } noraise {
        _ => false
      }
    })
    guard raised is Some(true) else {
      fail("Watcher::wait not interrupted by close")
    }
  }
}
