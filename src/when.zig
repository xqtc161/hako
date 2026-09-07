const std = @import("std");
const Io = std.Io;
const ansi = @import("ansi.zig");
const linux = std.os.linux;
const posix = std.posix;

pub fn exec(io: Io, args: []const [:0]const u8) !void {
    const r = linux.inotify_init1(linux.IN.CLOEXEC);
    if (linux.errno(r) != .SUCCESS)
        return error.InotifyInit;

    const fd: std.posix.fd_t = @intCast(r);
    defer _ = linux.close(fd);

    const wd = linux.inotify_add_watch(
        @intCast(fd),
        args[1],
        linux.IN.MODIFY,
    );
    if (linux.errno(wd) != .SUCCESS)
        return error.InotifyAddWatchError;

    const cmd = blk: {
        if (std.mem.eql(u8, args[2], "--") and args.len >= 3)
            break :blk args[3..];
        return error.MissingCommand;
    };

    var child: ?std.process.Child = null;

    var pollfds = [_]posix.pollfd{.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 }};

    var pending = false;

    var event: [4 * 1024]u8 = undefined;
    while (true) {
        pollfds[0].revents = 0;

        const ready = try posix.poll(
            &pollfds,
            if (pending) 10 else -1,
        );

        if (ready == 0) {
            // std.debug.print("[*] debounce -> spawn\n", .{});
            restart(io, cmd, &child) catch |err| {
                std.debug.print("{s}[-] error:{s} {any}{s}\n", .{
                    ansi.red ++ ansi.dim,
                    ansi.reset ++ ansi.bold,
                    err,
                    ansi.reset,
                });
            };
            pending = false;
            continue;
        }

        if (pollfds[0].revents & posix.POLL.IN != 0) {
            const nb = try posix.read(fd, &event);
            _ = nb;

            pending = true;
        }

        // var buf: [128]u8 = undefined;
        // const event_parsed = inotifyEventName(nb, &buf);
        // std.debug.print("{s}[*] {s}{s}\n", .{ ansi.green ++ ansi.dim, event_parsed, ansi.reset });
    }
}

fn restart(io: std.Io, cmd: []const [:0]const u8, child: *?std.process.Child) !void {
    if (child.*) |*c| {
        _ = c.kill(io);
        child.* = null;
    }
    child.* = try std.process.spawn(io, .{
        .argv = cmd,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
}

fn inotifyEventName(mask: usize, buf: []u8) []const u8 {
    const Event = struct { flag: u32, name: []const u8 };
    const events = [_]Event{
        .{ .flag = linux.IN.ACCESS, .name = "IN_ACCESS" },
        .{ .flag = linux.IN.MODIFY, .name = "IN_MODIFY" },
        .{ .flag = linux.IN.ATTRIB, .name = "IN_ATTRIB" },
        .{ .flag = linux.IN.CLOSE_WRITE, .name = "IN_CLOSE_WRITE" },
        .{ .flag = linux.IN.CLOSE_NOWRITE, .name = "IN_CLOSE_NOWRITE" },
        .{ .flag = linux.IN.OPEN, .name = "IN_OPEN" },
        .{ .flag = linux.IN.MOVED_FROM, .name = "IN_MOVED_FROM" },
        .{ .flag = linux.IN.MOVED_TO, .name = "IN_MOVED_TO" },
        .{ .flag = linux.IN.CREATE, .name = "IN_CREATE" },
        .{ .flag = linux.IN.DELETE, .name = "IN_DELETE" },
        .{ .flag = linux.IN.DELETE_SELF, .name = "IN_DELETE_SELF" },
        .{ .flag = linux.IN.MOVE_SELF, .name = "IN_MOVE_SELF" },
        .{ .flag = linux.IN.UNMOUNT, .name = "IN_UNMOUNT" },
        .{ .flag = linux.IN.Q_OVERFLOW, .name = "IN_Q_OVERFLOW" },
        .{ .flag = linux.IN.IGNORED, .name = "IN_IGNORED" },
        .{ .flag = linux.IN.ISDIR, .name = "IN_ISDIR" },
    };

    var w: std.Io.Writer = .fixed(buf);
    var any = false;
    for (events) |e| {
        if (mask & e.flag != 0) {
            if (any) w.writeAll(", ") catch break;
            w.writeAll(e.name) catch break;
            any = true;
        }
    }
    if (!any) return "0";
    return buf[0..w.end];
}
