const std = @import("std");
const ashet = @import("../../main.zig");

const c = @cImport({
    @cInclude("tusb.h");
});

const tusb_desc_endpoint_t = c.tusb_desc_endpoint_t;
const tusb_rhport_init_t = c.tusb_rhport_init_t;
const tusb_speed_t = c.tusb_speed_t;

pub const RHPort = enum(u8) {
    first = 0,
    _,
};

pub const DeviceAddr = enum(u8) {
    _,
};

pub const EndPointAddr = enum(u8) {
    _,
};

// Abort a queued transfer. Note: it can only abort transfer that has not been started
// Return true if a queued transfer is aborted, false if there is no transfer to abort
export fn hcd_edpt_abort_xfer(rhport: RHPort, dev_addr: DeviceAddr, ep_addr: EndPointAddr) bool {
    _ = rhport;
    _ = dev_addr;
    _ = ep_addr;
    @panic("hcd_edpt_abort_xfer not implemented yet!");
}

// Open an endpoint
export fn hcd_edpt_open(rhport: RHPort, daddr: DeviceAddr, ep_desc: *const tusb_desc_endpoint_t) bool {
    _ = rhport;
    _ = daddr;
    _ = ep_desc;
    @panic("hcd_edpt_open not implemented yet!");
}

// Submit a transfer, when complete hcd_event_xfer_complete() must be invoked
export fn hcd_edpt_xfer(rhport: RHPort, daddr: DeviceAddr, ep_addr: EndPointAddr, buffer: [*]u8, buflen: u16) bool {
    _ = rhport;
    _ = daddr;
    _ = ep_addr;
    _ = buffer;
    _ = buflen;
    @panic("hcd_edpt_xfer not implemented yet!");
}

// Initialize controller to host mode
export fn hcd_init(rhport: RHPort, rh_init: *const tusb_rhport_init_t) bool {
    _ = rhport;
    _ = rh_init;
    @panic("hcd_init not implemented yet!");
}

// HCD closes all opened endpoints belong to this device
export fn hcd_device_close(rhport: RHPort, dev_addr: DeviceAddr) void {
    _ = rhport;
    _ = dev_addr;
    @panic("hcd_device_close not implemented yet!");
}

// Disable USB interrupt
export fn hcd_int_disable(rhport: RHPort) void {
    _ = rhport;
    @panic("hcd_int_disable not implemented yet!");
}

// Enable USB interrupt
export fn hcd_int_enable(rhport: RHPort) void {
    _ = rhport;
    @panic("hcd_int_enable not implemented yet!");
}

// Interrupt Handler
export fn hcd_int_handler(rhport: RHPort, in_isr: bool) void {
    _ = rhport;
    _ = in_isr;
    @panic("hcd_int_handler not implemented yet!");
}

// Get the current connect status of roothub port
export fn hcd_port_connect_status(rhport: RHPort) bool {
    _ = rhport;
    @panic("hcd_port_connect_status not implemented yet!");
}

// Reset USB bus on the port. Return immediately, bus reset sequence may not be complete.
// Some port would require hcd_port_reset_end() to be invoked after 10ms to complete the reset sequence.
export fn hcd_port_reset(rhport: RHPort) void {
    _ = rhport;
    @panic("hcd_port_reset not implemented yet!");
}

// Complete bus reset sequence, may be required by some controllers
export fn hcd_port_reset_end(rhport: RHPort) void {
    _ = rhport;
    @panic("hcd_port_reset_end not implemented yet!");
}

// Get port link speed
export fn hcd_port_speed_get(rhport: RHPort) tusb_speed_t {
    _ = rhport;
    @panic("hcd_port_speed_get not implemented yet!");
}

// Submit a special transfer to send 8-byte Setup Packet, when complete hcd_event_xfer_complete() must be invoked
export fn hcd_setup_send(rhport: RHPort, daddr: DeviceAddr, setup_packet: *const [8]u8) void {
    _ = rhport;
    _ = daddr;
    _ = setup_packet;
    @panic("hcd_setup_send not implemented yet!");
}

// Invoked when received report from device via interrupt endpoint
// Note: if there is report ID (composite), it is 1st byte of report
export fn tuh_hid_report_received_cb(dev_addr: DeviceAddr, idx: u8, report: [*]const u8, len: u16) void {
    _ = dev_addr;
    _ = idx;
    _ = report;
    _ = len;
    @panic("tuh_hid_report_received_cb not implemented yet!");
}

// Get current milliseconds, required by some port/configuration without RTOS
export fn tusb_time_millis_api() u32 {
    return ashet.time.Instant.now().ms_since_start();
}

// Delay in milliseconds, use tusb_time_millis_api() by default. required by some port/configuration with no RTOS
export fn tusb_time_delay_ms_api(ms: u32) void {
    // TODO: Implement thread suspending here:

    const start = tusb_time_millis_api();
    while ((tusb_time_millis_api() - start) < ms) {
        //
    }
}
