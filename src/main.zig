const r4os = @import("r4os");

var driver_api: ?*const r4os.r4dev.DriverApi2 = null;
var activated = false;

comptime {
    if (!@import("builtin").is_test) asm (r4os.technical2.driverEntriesAsm("xhci_init", "xhci_shutdown"));
}

// XHCI.R4D is deliberately a thin activation owner. The kernel backend is
// the sole PCI/MMIO/DMA, transfer-ring, event and shutdown implementation.
// This keeps module ownership/unload visible without probing the controller
// twice or exporting kernel hardware internals into a loadable module.
export fn xhci_init(api: *const r4os.r4dev.DriverApi2) callconv(.c) i32 {
    var ctx = r4os.r4dev.DriverContext2.init(api);
    if (!ctx.requires(.{ "activate_usb_host_controller", "unregister_usb_host_controller" })) {
        ctx.logError("XHCI.R4D driver api mismatch");
        return -3;
    }
    if (activated) return -2;
    driver_api = api;
    const result = ctx.activateUsbHostController("XHCI", r4os.abi.usb_host_source_preload);
    if (result < 0) {
        driver_api = null;
        ctx.logError("XHCI.R4D canonical host activation failed");
        return result;
    }
    activated = true;
    ctx.logInfo("XHCI.R4D canonical kernel host activated; owner=preload");
    return 0;
}

export fn xhci_shutdown() callconv(.c) i32 {
    if (!activated) {
        driver_api = null;
        return 0;
    }
    const api = driver_api orelse return -1;
    var ctx = r4os.r4dev.DriverContext2.init(api);
    const result = ctx.unregisterUsbHostController("XHCI");
    if (result == 0) {
        activated = false;
        driver_api = null;
    }
    return result;
}

test "xHCI activation owner retains state until actual unregister and rejects duplicate Init" {
    const testing = @import("std").testing;
    const std = @import("std");
    const F = struct {
        var activations: usize = 0;
        var retirements: usize = 0;
        var result: i32 = -2;
        fn activate(name: [*:0]const u8, source: u32) callconv(.c) i32 {
            if (!std.mem.eql(u8, std.mem.span(name), "XHCI") or source != r4os.abi.usb_host_source_preload) return -1;
            activations += 1;
            return 0;
        }
        fn retire(name: [*:0]const u8) callconv(.c) i32 {
            if (!std.mem.eql(u8, std.mem.span(name), "XHCI")) return -1;
            retirements += 1;
            return result;
        }
    };
    var api: r4os.r4dev.DriverApi2 = undefined;
    @memset(std.mem.asBytes(&api), 0);
    api.magic = r4os.technical2.abi.driver_magic;
    api.version = r4os.technical2.abi.driver_version;
    api.size = @sizeOf(@TypeOf(api));
    api.activate_usb_host_controller = F.activate;
    try testing.expectEqual(@as(i32, -3), xhci_init(&api));
    try testing.expectEqual(@as(usize, 0), F.activations);
    api.unregister_usb_host_controller = F.retire;
    try testing.expectEqual(@as(i32, 0), xhci_init(&api));
    try testing.expectEqual(@as(i32, -2), xhci_init(&api));
    try testing.expectEqual(@as(usize, 1), F.activations);
    try testing.expectEqual(@as(i32, -2), xhci_shutdown());
    try testing.expect(activated and driver_api == &api);
    F.result = 0;
    try testing.expectEqual(@as(i32, 0), xhci_shutdown());
    try testing.expect(!activated and driver_api == null);
    try testing.expectEqual(@as(i32, 0), xhci_shutdown());
    try testing.expectEqual(@as(usize, 2), F.retirements);
}
