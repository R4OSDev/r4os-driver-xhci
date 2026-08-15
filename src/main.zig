const r4os = @import("r4os");

const CLASS_SERIAL_BUS: u8 = 0x0C;
const SUBCLASS_USB: u8 = 0x03;
const PROGIF_XHCI: u8 = 0x30;

const XhciState = extern struct {
    present: u32 = 0,
    mapped: u32 = 0,
    dma_ready: u32 = 0,
    ports: u32 = 0,
    scans: u64 = 0,
    controls: u64 = 0,
    failures: u64 = 0,
    mmio_base: u64 = 0,
    mmio_size: u32 = 0,
};

var state: XhciState = .{};
var mmio: r4os.abi.MmioRegion = .{};
var dma: r4os.abi.DmaBuffer = .{};

var backend: r4os.abi.UsbHostController = .{
    .source = r4os.abi.usb_host_source_preload,
    .context = &state,
    .port_scan = portScan,
    .control_transfer = controlTransfer,
    .poll = poll,
    .shutdown = shutdownBackend,
    .status = status,
};

comptime {
    asm (r4os.r4dev.driverEntriesAsm("xhci_init", "xhci_shutdown"));
}

export fn xhci_init(api: *const r4os.r4dev.DriverApi) callconv(.c) i32 {
    var ctx = r4os.r4dev.DriverContext.init(api);
    if (!ctx.apiCompatible()) {
        ctx.logError("XHCI.R4D driver api mismatch");
        return -3;
    }

    const info = findXhci(&ctx) orelse
        return registerPreloadBoundary(&ctx, "XHCI.R4D no xHCI controller found; preload boundary only");

    state.present = 1;
    if (ctx.pciEnableBusMaster(info, r4os.abi.pci_enable_memory_space) != 0) {
        return registerPreloadBoundary(&ctx, "XHCI.R4D bus master enable failed; legacy rescue required");
    }

    if (ctx.pciMapBar(info, 0, 4096, 0, &mmio) != 0 or mmio.virt_addr == 0) {
        return registerPreloadBoundary(&ctx, "XHCI.R4D BAR0 map failed; legacy rescue required");
    }
    state.mapped = 1;
    state.mmio_base = mmio.phys_addr;
    state.mmio_size = mmio.mapped_bytes;
    state.ports = readMaxPorts(mmio.virt_addr);

    if (ctx.allocDmaRegion(4096, 4096, &dma) == 0 and dma.phys_addr != 0 and dma.virt_addr != 0) {
        state.dma_ready = 1;
    } else {
        ctx.logWarn("XHCI.R4D DMA smoke allocation failed");
    }

    if (ctx.registerUsbHostController("XHCI", &backend) != 0) {
        ctx.logError("XHCI.R4D host backend register failed");
        return -4;
    }

    ctx.logInfo("XHCI.R4D preload host backend ready; built-in legacy rescue remains data path");
    return 0;
}

export fn xhci_shutdown() callconv(.c) i32 {
    return 0;
}

fn portScan(context: ?*anyopaque) callconv(.c) i32 {
    const s = xhciState(context) orelse return -1;
    s.scans += 1;
    return 0;
}

fn controlTransfer(context: ?*anyopaque, device: *const r4os.abi.UsbDeviceHandle, request: *const r4os.abi.UsbControlRequest, buffer: [*]u8, len: u32) callconv(.c) i32 {
    _ = device;
    _ = request;
    _ = buffer;
    _ = len;
    const s = xhciState(context) orelse return -1;
    s.controls += 1;
    s.failures += 1;
    return -1;
}

fn poll(context: ?*anyopaque) callconv(.c) i32 {
    _ = context;
    return 0;
}

fn shutdownBackend(context: ?*anyopaque) callconv(.c) i32 {
    _ = context;
    return 0;
}

fn status(context: ?*anyopaque, out: *r4os.abi.UsbHostStatus) callconv(.c) i32 {
    const s = xhciState(context) orelse return -1;
    out.* = .{
        .state = 1,
        .source = r4os.abi.usb_host_source_preload,
        .ports = s.ports,
        .devices = 0,
        .transfers = s.controls,
        .failures = s.failures,
    };
    return 0;
}

fn xhciState(context: ?*anyopaque) ?*XhciState {
    const raw = context orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn findXhci(ctx: *const r4os.r4dev.DriverContext) ?r4os.abi.PciDeviceInfo {
    var index: u32 = 0;
    while (true) {
        var info: r4os.abi.PciDeviceInfo = .{};
        const found = ctx.pciFindByClass(CLASS_SERIAL_BUS, SUBCLASS_USB, index, &info);
        if (found < 0) return null;
        index = @as(u32, @intCast(found)) + 1;
        if (info.prog_if == PROGIF_XHCI) return info;
    }
}

fn registerPreloadBoundary(ctx: *const r4os.r4dev.DriverContext, reason: [*:0]const u8) i32 {
    state.present = 0;
    state.mapped = 0;
    state.dma_ready = 0;
    state.ports = 0;
    state.mmio_base = 0;
    state.mmio_size = 0;
    ctx.logWarn(reason);
    if (ctx.registerUsbHostController("XHCI", &backend) != 0) {
        ctx.logError("XHCI.R4D host backend register failed");
        return -4;
    }
    ctx.logInfo("XHCI.R4D preload host boundary ready; built-in legacy rescue remains data path");
    return 0;
}

fn readMaxPorts(base: u64) u32 {
    const hcsparams1_addr = base + 0x04;
    const value = mmioRead32(hcsparams1_addr);
    return (value >> 24) & 0xff;
}

fn mmioRead32(addr: u64) u32 {
    const ptr: *volatile u32 = @ptrFromInt(addr);
    return ptr.*;
}
