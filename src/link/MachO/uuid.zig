const std = @import("std");
const fs = std.fs;
const mem = std.mem;

const Allocator = mem.Allocator;
const Compilation = @import("../../Compilation.zig");
const Md5 = std.crypto.hash.Md5;
const Hasher = @import("hasher.zig").ParallelHasher;

/// Somewhat random chunk size for MD5 hash calculation.
pub const chunk_size = 0x4000;

/// Calculates Md5 hash of each chunk in parallel and then hashes all Md5 hashes to produce
/// the final digest.
/// While this is NOT a correct MD5 hash of the contents, this methodology is used by LLVM/LLD
/// and we will use it too as it seems accepted by Apple OSes.
/// TODO LLD also hashes the output filename to disambiguate between same builds with different
/// output files. Should we also do that?
pub fn calcUuid(comp: *const Compilation, file: fs.File, file_size: u64, out: *[Md5.digest_length]u8) !void {
    const total_hashes = mem.alignForward(u64, file_size, chunk_size) / chunk_size;

    const hashes = try comp.gpa.alloc([Md5.digest_length]u8, total_hashes);
    defer comp.gpa.free(hashes);

    var hasher = Hasher(Md5){};
    try hasher.hash(comp.gpa, comp.thread_pool, file, hashes, .{
        .chunk_size = chunk_size,
        .max_file_size = file_size,
    });

    const final_buffer = try comp.gpa.alloc(u8, total_hashes * Md5.digest_length);
    defer comp.gpa.free(final_buffer);

    for (hashes, 0..) |hash, i| {
        mem.copy(u8, final_buffer[i * Md5.digest_length ..][0..Md5.digest_length], &hash);
    }

    Md5.hash(final_buffer, out, .{});
    conform(out);
}

inline fn conform(out: *[Md5.digest_length]u8) void {
    // LC_UUID uuids should conform to RFC 4122 UUID version 4 & UUID version 5 formats
    out[6] = (out[6] & 0x0F) | (3 << 4);
    out[8] = (out[8] & 0x3F) | 0x80;
}
