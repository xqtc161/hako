// TODO: parse events, handle CREATE | MOVED_TO + ISDIR with new watchers
pub fn exec(io: Io, args: []const [:0]const u8) !void {
    const path, const cmd = blk: {
        if (args.len < 4)
            return error.MissingArgs;

        if (!std.mem.eql(u8, args[2], "--"))
            return error.MissingCommand;

        break :blk .{ args[1], args[3..] };
    };

    const r = linux.inotify_init1(linux.IN.CLOEXEC);
    if (linux.errno(r) != .SUCCESS)
        return error.InotifyInit;

    const fd: std.posix.fd_t = @intCast(r);
    defer _ = linux.close(fd);

    const mask = linux.IN.CLOSE_WRITE |
        linux.IN.CREATE |
        linux.IN.DELETE |
        linux.IN.MOVED_FROM |
        linux.IN.MOVED_TO;

    // TODO: recurse subdirs
    const wd = linux.inotify_add_watch(
        @intCast(fd),
        path,
        mask,
    );
    if (linux.errno(wd) != .SUCCESS)
        return error.InotifyAddWatchError;

    var child: ?std.process.Child = null;
    defer child.?.kill(io);

    var pollfds = [_]posix.pollfd{.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 }};

    var pending = false;

    const debounce_ms = 50;

    var event: [4 * 1024]u8 = undefined;
    while (true) {
        pollfds[0].revents = 0;

        const ready = try posix.poll(
            &pollfds,
            if (pending) debounce_ms else -1,
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

const std = @import("std");
const Io = std.Io;
const linux = std.os.linux;
const posix = std.posix;

const ansi = @import("ansi.zig");
