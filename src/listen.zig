const std = @import("std");
const Io = std.Io;

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

pub fn exec(io: Io, args: []const [:0]const u8) !void {
    if (args.len < 2)
        return error.InvalidArguments;

    const protocol = try Protocol.fromString(args[1]);

    var unix_path: ?[]const u8 = null;

    var server: Io.net.Server = switch (protocol) {
        .tcp => blk: {
            if (args.len != 4) {
                std.debug.print(
                    "usage: hako listen tcp <address> <port>\n",
                    .{},
                );
                return error.InvalidArguments;
            }

            const port = std.fmt.parseInt(u16, args[3], 10) catch
                return error.InvalidPort;

            const address = try resolveTcpAddress(
                io,
                args[2],
                port,
            );

            break :blk try address.listen(io, .{
                .reuse_address = true,
            });
        },

        .unix => blk: {
            if (args.len != 3) {
                std.debug.print(
                    "usage: hako listen unix <path>\n",
                    .{},
                );
                return error.InvalidArguments;
            }

            const address: Io.net.UnixAddress = try .init(args[2]);

            const s = try address.listen(io, .{});

            unix_path = args[2];

            break :blk s;
        },
    };

    defer {
        server.deinit(io);

        if (unix_path) |path|
            Io.Dir.cwd().deleteFile(io, path) catch {};
    }

    std.debug.print("[+] listening\n", .{});

    var stream = try server.accept(io);
    defer stream.close(io);

    std.debug.print("[+] connection accepted\n", .{});
}
