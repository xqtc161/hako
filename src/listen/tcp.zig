const std = @import("std");
const Io = std.Io;
const util = @import("util.zig");

pub fn exec(io: Io, args: []const [:0]const u8) !void {
    var server = blk: {
        const address = try argsFromSlice(io, args);
        break :blk try address.listen(io, .{
            .reuse_address = true,
        });
    };

    defer server.deinit(io);

    try util.redir(io, &server);
}

fn argsFromSlice(io: Io, args: []const [:0]const u8) !Io.net.IpAddress {
    if (args.len < 2 or args.len != 4) {
        std.debug.print(
            "usage: hako listen tcp <address> <port>\n",
            .{},
        );
        return error.InvalidArguments;
    }
    const port = std.fmt.parseInt(u16, args[3], 10) catch return error.InvalidPort;
    const address = try resolveTcpAddress(
        io,
        args[2],
        port,
    );
    return address;
}

fn resolveTcpAddress(
    io: Io,
    host: []const u8,
    port: u16,
) !Io.net.IpAddress {
    if (std.mem.eql(u8, host, "*"))
        return .{ .ip4 = .unspecified(port) };

    if (Io.net.IpAddress.resolve(io, host, port)) |address| {
        return address;
    } else |_| {}

    const hostname: Io.net.HostName = try .init(host);

    var canonical_name_buffer: [Io.net.HostName.max_len]u8 = undefined;
    var result_buffer: [16]Io.net.HostName.LookupResult = undefined;
    var results: Io.Queue(Io.net.HostName.LookupResult) =
        .init(&result_buffer);

    try hostname.lookup(io, &results, .{
        .port = port,
        .canonical_name_buffer = &canonical_name_buffer,
    });

    while (results.getOne(io)) |result| {
        switch (result) {
            .address => |address| return address,
            .canonical_name => {},
        }
    } else |err| switch (err) {
        error.Closed => return error.UnknownHostName,
        error.Canceled => return err,
    }
}
