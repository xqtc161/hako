const std = @import("std");
const Io = std.Io;
const util = @import("util.zig");

pub fn exec(io: Io, args: []const [:0]const u8) !void {
    if (args.len < 2 or args.len != 3) {
        std.debug.print(
            "usage: hako listen unix <path>\n",
            .{},
        );
        return error.InvalidArguments;
    }

    var unix_path: ?[]const u8 = null;

    var server = blk: {
        const address: Io.net.UnixAddress = try .init(args[2]);

        const s = try address.listen(io, .{});

        unix_path = args[2];

        break :blk s;
    };

    defer {
        server.deinit(io);

        if (unix_path) |path|
            Io.Dir.cwd().deleteFile(io, path) catch {};
    }
    try util.redir(io, &server);
}
