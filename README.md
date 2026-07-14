# container-zig

<p align="center">
  <img src="assets/container-zig-mascot.png" alt="container-zig logo mascot" width="260">
</p>

[简体中文](README-zh.md)

`container-zig` is an unofficial Zig SDK for the Docker Engine API.

The `zig-0.15` branch targets Zig `0.15.2`, exposes the import module `container_zig`, and maps Docker Engine API v1.55 endpoints to explicit Zig module functions such as `docker.system.ping`, `docker.container.list`, and `docker.image.build`.

## Status

- Docker Engine API target: v1.55.
- Negotiated API range: v1.40 through v1.55.
- Implemented endpoint coverage: 108 / 108 operations.
- Transport support: Unix socket, TCP, TLS, Windows named pipe, SSH, and custom adapters.
- Default socket path: `/var/run/docker.sock`.
- HTTP, TLS, sockets, processes, and WebSocket framing use the Zig `0.15.2` standard library. SSH transport executes the user's `ssh` binary directly without a shell.

This project is not an official Docker SDK. Docker's official documentation currently lists Go and Python SDKs and direct Engine API usage.

## Requirements

- Zig `0.15.2`.
- Docker Engine reachable through one of the supported transports.
- A daemon API version compatible with the endpoints you call.

Run `docker version` to inspect the daemon API version before using endpoints added in recent Docker releases.

The `main` branch targets Zig `0.16.0`; `zig-0.17` tracks the next development snapshot.

## Version Support

The project actively maintains the Zig release selected by `main` and its immediately previous and next versions. When a new Zig release moves a branch outside this three-version window, that branch remains available for existing users but receives no further bug, security, or compatibility maintenance.

## Design

`Client.init(allocator, config)` returns an error union and validates the selected transport. Call `try client.connect()` before any versioned endpoint. Automatic and fixed modes both validate the daemon's supported API range.

Build contexts, image archives, and container archives use `docker.Client.Upload`, which supports bytes and incremental readers. Image pull, push, build, and load return `docker.image.ProgressStream`; callers must inspect every item because Docker can report a daemon error after HTTP 200. Attach and Exec start return `docker.stream.Session`, which exposes raw TTY bytes or decoded non-TTY stdout/stderr frames.

## Install

Add the package to another Zig project:

```sh
zig fetch --save=container_zig git+https://github.com/GuangYiL/container-zig#zig-0.15
```

Then wire the module in the consumer `build.zig`:

```zig
const container_zig = b.dependency("container_zig", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("container_zig", container_zig.module("container_zig"));
```

## Quick Start

```zig
const std = @import("std");
const docker = @import("container_zig");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try docker.Client.init(allocator, .{});
    defer client.deinit();

    try client.connect();

    var ping = try docker.system.ping(allocator, &client);
    defer ping.deinit();

    var version = try docker.system.version(allocator, &client);
    defer version.deinit();

    std.log.info("Docker {s}, API {s}", .{
        version.engine_version,
        ping.api_version,
    });
}
```

`Client.connect` requests `/version`, intersects the daemon range with the SDK range, and stores the selected API version. Unversioned paths are not used for normal endpoint calls.

Run the included demo with automatic socket discovery or pass a custom socket path:

```sh
zig build run
zig build run -- "unix://$HOME/.orbstack/run/docker.sock"
zig build run -- "tcp://127.0.0.1:2375"
zig build run -- "https://docker.example.com:2376"
zig build run -- "ssh://builder@docker.example.com"
```

Without an argument, the demo checks `DOCKER_HOST` first. On Unix it then discovers an available socket in this order:
`/var/run/docker.sock`, `$HOME/.orbstack/run/docker.sock`, and `$HOME/.docker/run/docker.sock`. An explicitly
configured path fails immediately if it is invalid; discovery does not silently replace it.

## Transports

```zig
var client = try docker.Client.init(allocator, .{
    .transport = .{
        .unix_socket = .{
            .path = "/path/to/docker.sock",
        },
    },
});
defer client.deinit();
try client.connect();
```

Select `.tcp`, `.tls`, `.named_pipe`, or `.ssh` in the same explicit `Transport` union. Plain remote TCP is rejected by default; only loopback is accepted unless `allow_insecure_remote = true` is deliberately set. TLS verifies the daemon certificate with Zig's standard certificate bundle. Windows defaults to `\\.\pipe\docker_engine`. SSH runs `docker system dial-stdio` on the remote host and supports user, port, identity file, and explicit extra arguments. `.custom` accepts a caller-provided duplex connector.

## Fixed API Version

Use a fixed API version when compatibility testing requires one exact version:

```zig
var client = try docker.Client.init(allocator, .{
    .api_version = .{ .fixed = .{ .major = 1, .minor = 55 } },
});
defer client.deinit();
try client.connect();
```

If the daemon range does not contain that version, `connect` fails instead of silently falling back.

## API Shape

The public surface is module-oriented:

```zig
const docker = @import("container_zig");

const filters = try docker.params.filters(allocator, &.{
    .{ .name = "status", .values = &.{"running"} },
});
defer allocator.free(filters);

var containers = try docker.container.list(allocator, &client, .{
    .all = true,
    .filters = filters,
});
defer containers.deinit();

for (containers.items) |container| {
    if (container.id) |id| {
        std.log.info("container {s}", .{id});
    }
}
```

Per-call endpoint settings use direct resource declarations such as `docker.container.ListOptions` and
`docker.image.BuildOptions`. Persistent object configuration stays under the object that owns it, such as
`docker.Client.Config`. This keeps endpoint calls discoverable without artificial `Build.Config` namespace wrappers.

Common modules:

| Module | Examples |
| --- | --- |
| `docker.system` | `ping`, `pingText`, `version`, `info`, `events`, `dataUsage`, `auth` |
| `docker.container` | `create`, `list`, `inspect`, `logs`, `attach`, `start`, `stop`, `remove`, `prune` |
| `docker.image` | `list`, `build`, `create`, `inspect`, `attestations`, `push`, `tag`, `remove`, `search`, `load` |
| `docker.volume` | `list`, `create`, `inspect`, `update`, `remove`, `prune` |
| `docker.network` | `list`, `create`, `inspect`, `connect`, `disconnect`, `remove`, `prune` |
| `docker.swarm` | `inspect`, `init`, `join`, `leave`, `update`, `unlockKey`, `unlock` |
| `docker.service` | `list`, `create`, `inspect`, `update`, `logs`, `remove` |
| `docker.exec` | `create`, `start`, `resize`, `inspect` |

Finite response models own their returned memory and expose `deinit`. Streaming endpoints expose explicit stream wrappers that must also be deinitialized. `docker.stream.RecordDecoder` accepts NDJSON and RFC 7464 JSON sequences, and `docker.stream.MultiplexDecoder` preserves binary stdout/stderr frames.

Image attestations are returned as a finite owned list, and platform filters use the typed OCI platform model:

```zig
var attestations = try docker.image.attestations(allocator, &client, "example/app:latest", .{
    .platforms = &.{.{ .os = "linux", .architecture = "amd64" }},
    .statement = true,
});
defer attestations.deinit();
```

Use `docker.params.filters` for Docker filter query values and `docker.params.stringMap` for JSON object parameters such as build args and labels. Both helpers return allocator-owned JSON bytes.

## Streaming and Interactive I/O

Uploads do not need to be buffered in memory:

```zig
var tar_reader = std.Io.Reader.fixed(tar_bytes);
var progress = try docker.image.build(allocator, &client, .{
    .context = .{ .stream = .{
        .reader = &tar_reader,
        .content_length = tar_bytes.len,
    } },
});
defer progress.deinit();

while (try progress.next(allocator)) |item_value| {
    var item = item_value;
    defer item.deinit();
    switch (item) {
        .progress => |message| std.log.info("{?s}", .{message.status}),
        .daemon_error => |_| return error.DaemonStreamError,
    }
}
```

`docker.exec.start` and `docker.container.attach` return `docker.stream.Session`. Use `nextFrame` for non-TTY sessions; use `reader` directly for TTY bytes. `writer` and `closeStdin` provide the duplex input side. Logs use the same 8-byte Docker multiplex decoder. Events and stats are incrementally decoded across arbitrary network buffer boundaries.

For non-success responses, `Client.Config.api_error_handler` receives a structured `ApiFailure` containing method, endpoint, status, daemon message, and negotiated version. `Client.request` remains the raw escape hatch when an endpoint is newer than the typed SDK surface.

Retries are disabled by default. An explicit `retry_policy` can retry transient connection failures only for bodyless GET and HEAD requests; mutating requests and HTTP status failures are never retried automatically.

## Memory Ownership

- Public finite results own their returned memory and expose `deinit`.
- Public result wrappers store their allocator when they need to release nested owned data without more arguments.
- `Client.init` receives the allocator explicitly; endpoint functions that allocate place the allocator first.
- Methods keep the receiver first, including methods that also accept an allocator.
- Internal nested model cleanup keeps Zig method shape as `value.deinit(allocator)`.
- Large read-only responses may use an internal arena when the whole result is released as one unit.

## Transport Notes

- TLS uses Zig's standard trust store and server-certificate verification. Client-certificate injection is available through a custom transport because the targeted standard HTTP client does not expose mTLS client identities.
- Named pipe transport is available only on Windows.
- SSH transport requires an `ssh` executable and a remote Docker CLI that supports `docker system dial-stdio`.
- The `zig-0.15` branch is tested with Zig `0.15.2` and contains no Zig 0.16 compatibility shims.

## License

`container-zig` uses the same MIT License (Expat) text as Zig. See [LICENSE](LICENSE).

## References

- [Docker Engine API](https://docs.docker.com/reference/api/engine/)
- [Docker Engine API v1.55 reference](https://docs.docker.com/reference/api/engine/version/v1.55/)
- [Docker Engine API version history](https://docs.docker.com/reference/api/engine/version-history/)
- [Zig 0.15.2 documentation](https://ziglang.org/documentation/0.15.2/)
