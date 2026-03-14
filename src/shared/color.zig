const std = @import("std");

pub const Rgba8 = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub fn packRgba8(r: u8, g: u8, b: u8, a: u8) u32 {
    return @bitCast(Rgba8{
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    });
}

pub fn unpackRgba8(value: u32) Rgba8 {
    return @bitCast(value);
}

test "U12 color_pack_unpack_roundtrip" {
    const packed_value = packRgba8(0x12, 0x34, 0x56, 0x78);
    const unpacked = unpackRgba8(packed_value);

    try std.testing.expectEqual(@as(u8, 0x12), unpacked.r);
    try std.testing.expectEqual(@as(u8, 0x34), unpacked.g);
    try std.testing.expectEqual(@as(u8, 0x56), unpacked.b);
    try std.testing.expectEqual(@as(u8, 0x78), unpacked.a);
}
