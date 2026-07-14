const std = @import("std");

const http_transport = @import("../http_transport.zig");
const multiplex = @import("multiplex.zig");

pub const Session = struct {
    duplex: http_transport.Duplex,
    tty: bool,
    decoder: ?multiplex.Decoder,
    max_frame_bytes: usize,

    pub fn init(duplex: http_transport.Duplex, tty: bool, max_frame_bytes: usize) Session {
        return .{
            .duplex = duplex,
            .tty = tty,
            .decoder = null,
            .max_frame_bytes = max_frame_bytes,
        };
    }

    pub fn reader(self: *Session) *std.Io.Reader {
        return self.duplex.reader();
    }

    pub fn writer(self: *Session) *std.Io.Writer {
        return self.duplex.writer();
    }

    pub fn nextFrame(self: *Session, allocator: std.mem.Allocator) !?multiplex.Frame {
        if (self.tty) return error.TtyUsesRawStream;
        if (self.decoder == null) {
            self.decoder = .init(self.duplex.reader(), self.max_frame_bytes);
        }
        return self.decoder.?.next(allocator);
    }

    pub fn closeStdin(self: *Session) !void {
        return self.duplex.closeWrite();
    }

    pub fn deinit(self: *Session) void {
        self.duplex.deinit();
        self.* = undefined;
    }
};
