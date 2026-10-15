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
fn pipe_for_test() -> (IoHandle, IoHandle) raise {
  let context = "pipe_for_test()"
  let (r, w) = @fd_util.pipe(
    read_end_is_async=true,
    write_end_is_async=true,
    context~,
  )
  (IoHandle::from_fd(r, kind=Pipe), IoHandle::from_fd(w, kind=Pipe))
}

///|
/// Run `f`, which is expected to block on `handle`.
/// Once `f` is waiting on `handle`, close `handle` from another task.
/// Return the error raised by `f`.
async fn close_while_waiting(
  handle : IoHandle,
  f : async () -> Unit,
  is_waiting~ : (IoHandle) -> Bool,
) -> Error {
  @async.with_task_group() <| group => {
    // `no_wait`: do not hang if `f` fails before it starts waiting
    group.spawn_bg(no_wait=true) <| () => {
      while !is_waiting(handle) {
        @async.pause()
      }
      handle.close()
    }
    let result = @async.with_timeout_opt(1000, () => {
      try f() catch {
        err => Some(err)
      } noraise {
        _ => None
      }
    })
    match result {
      None => fail("not woken up by close")
      Some(None) => fail("returned normally after close")
      Some(Some(err)) => err
    }
  }
}

///|
fn assert_ebadf(err : Error, context~ : String) -> Unit raise {
  guard err is @os_error.OSError(errno, context=err_context) &&
    errno == @os_error.errno_EBADF &&
    err_context == context else {
    fail("unexpected error: \{err}")
  }
}

///|
async test "close wakes up pending read" {
  // Not supported on Windows yet, see `IoHandle::close`
  if platform is Windows {
    return
  }
  let (r, w) = pipe_for_test()
  defer w.close()
  defer r.close()
  let buf = FixedArray::make(16, b'\x00')
  let err = close_while_waiting(
    r,
    () => ignore(r.read(buf, offset=0, len=16, context="read")),
    is_waiting=handle => handle.read is Waiting(_),
  )
  assert_ebadf(err, context="read")
}

///|
async test "close wakes up pending write" {
  // Not supported on Windows yet, see `IoHandle::close`
  if platform is Windows {
    return
  }
  let (r, w) = pipe_for_test()
  defer r.close()
  defer w.close()
  let chunk = Bytes::make(4096, 0)
  let err = close_while_waiting(
    w,
    () => {
      // nobody reads from `r`, so the pipe eventually becomes full
      while true {
        ignore(w.write(chunk, offset=0, len=chunk.length(), context="write"))
      }
    },
    is_waiting=handle => handle.write is Waiting(_),
  )
  assert_ebadf(err, context="write")
}

// `wait_read`/`wait_write` are only available on Unix.
// The runtime check is still needed for the wasm target on Windows hosts.

///|
#cfg(not(platform="windows"))
async test "close wakes up wait_read" {
  if platform is Windows {
    return
  }
  let (r, w) = pipe_for_test()
  defer w.close()
  defer r.close()
  let err = close_while_waiting(r, () => r.wait_read(context="wait_read"), is_waiting=handle => {
    handle.read is Waiting(_)
  })
  assert_ebadf(err, context="wait_read")
}

///|
#cfg(not(platform="windows"))
async test "close wakes up wait_write" {
  if platform is Windows {
    return
  }
  let (r, w) = pipe_for_test()
  defer r.close()
  defer w.close()
  // fill the pipe, so that `wait_write` blocks
  let chunk = Bytes::make(4096, 0)
  while write_unix_ffi(w.fd, chunk, offset=0, len=chunk.length()) > 0 {

  }
  guard @os_error.is_nonblocking_io_error() else {
    @os_error.check_errno("fill pipe")
  }
  let err = close_while_waiting(w, () => w.wait_write(context="wait_write"), is_waiting=handle => {
    handle.write is Waiting(_)
  })
  assert_ebadf(err, context="wait_write")
}

///|
#cfg(not(platform="windows"))
async test "wait on closed handle" {
  if platform is Windows {
    return
  }
  let (r, w) = pipe_for_test()
  r.close()
  w.close()
  let err = try r.wait_read(context="wait_read") catch {
    err => err
  } noraise {
    _ => fail("wait_read returned normally")
  }
  assert_ebadf(err, context="wait_read")
  let err = try w.wait_write(context="wait_write") catch {
    err => err
  } noraise {
    _ => fail("wait_write returned normally")
  }
  assert_ebadf(err, context="wait_write")
}
