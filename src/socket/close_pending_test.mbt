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
async test "close wakes up pending read" {
  // Not supported on Windows yet, see `@event_loop.IoHandle::close`
  if @event_loop.platform is Windows {
    return
  }
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let client = @socket.Tcp::connect(server.addr)
  let (peer, _) = server.accept()
  defer peer.close()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @async.sleep(50)
      client.close()
    }
    let raised = @async.with_timeout_opt(1000, () => {
      try client.read_some() catch {
        _ => true
      } noraise {
        _ => false
      }
    })
    guard raised is Some(true) else { fail("read not woken up by close") }
  }
}

///|
async test "close wakes up pending write" {
  // Not supported on Windows yet, see `@event_loop.IoHandle::close`
  if @event_loop.platform is Windows {
    return
  }
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let client = @socket.Tcp::connect(server.addr)
  let (peer, _) = server.accept()
  defer peer.close()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @async.sleep(50)
      client.close()
    }
    let chunk = Bytes::make(65536, 0)
    let raised = @async.with_timeout_opt(1000, () => {
      try {
        // `peer` never reads, so `write` eventually blocks
        while true {
          client.write(chunk)
        }
      } catch {
        _ => true
      } noraise {
        _ => false
      }
    })
    guard raised is Some(true) else { fail("write not woken up by close") }
  }
}

///|
async test "close wakes up pending accept" {
  // Not supported on Windows yet, see `@event_loop.IoHandle::close`
  if @event_loop.platform is Windows {
    return
  }
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @async.sleep(50)
      server.close()
    }
    let raised = @async.with_timeout_opt(1000, () => {
      try server.accept() catch {
        _ => true
      } noraise {
        (conn, _) => {
          conn.close()
          false
        }
      }
    })
    guard raised is Some(true) else { fail("accept not woken up by close") }
  }
}
