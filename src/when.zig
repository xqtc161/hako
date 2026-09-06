const std = @import("std");
const Io = std.Io;
const ansi = @import("ansi.zig");
const linux = std.os.linux;
const posix = std.posix;

pub fn exec(io: Io, args: []const [:0]const u8) !void {
    _ = io; // autofix
    const r = linux.inotify_init1(linux.IN.CLOEXEC);
    if (linux.errno(r) != .SUCCESS)
        return error.InotifyInit;

    const fd: std.posix.fd_t = @intCast(r);
    defer _ = linux.close(fd);

    const wd = linux.inotify_add_watch(
        @intCast(fd),
        args[1],
        linux.IN.ALL_EVENTS,
    );
    if (linux.errno(wd) != .SUCCESS)
        return error.InotifyWatch;

    var event: [4 * 1024]u8 = undefined;
    while (true) {
        const nb = try posix.read(fd, &event);
        if (linux.errno(nb) != .SUCCESS)
            return error.InotifyEventRead;
        std.debug.print("event\n", .{});
    }
}
