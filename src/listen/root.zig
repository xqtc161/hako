pub const unix = @import("unix.zig");
pub const tcp = @import("tcp.zig");

const Protocol = enum {
    tcp,
    unix,

    fn fromString(str: []const u8) !Protocol {
        if (std.mem.eql(u8, str, "tcp"))
            return .tcp;

        if (std.mem.eql(u8, str, "unix"))
            return .unix;

        std.debug.print(
            "[-] expected either 'tcp' or 'unix', got: {s}\n",
            .{str},
        );
        return error.InvalidProtocol;
    }
};

pub fn exec(io: std.Io, args: []const [:0]const u8) !void {
    if (args.len < 2)
        return error.InvalidArguments;

    const protocol = try Protocol.fromString(args[1]);

    switch (protocol) {
        .tcp => return try tcp.exec(io, args),
        .unix => return try unix.exec(io, args),
    }
    return;
}

const std = @import("std");
const listen = @This();
