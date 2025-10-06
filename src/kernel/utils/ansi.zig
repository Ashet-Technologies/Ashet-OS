//!
//! This file contains several useful ansi escape sequences that can be used for output formatting.
//!

const std = @import("std");

/// Clears the screen by:
/// 1. Set cursor position to (0,0) with "SGI H"
/// 2. Clear entire screen with "SGI 2J"
/// 3. Clear scrollback buffer with "SGI 3J"
pub const clear_screen = "\x1B[H\x1B[2J\x1B[3J" ++ sgi(.reset);

/// Returns a "select graphics rendition" code for the given rendition
///
/// Read more here: https://en.wikipedia.org/wiki/ANSI_escape_code#Select_Graphic_Rendition_parameters
pub fn sgi(comptime rendition: GraphicsRendition) []const u8 {
    return std.fmt.comptimePrint("\x1B[{}m", .{@intFromEnum(rendition)});
}

pub const GraphicsRendition = enum(u32) {
    reset = 0, // Reset or normal, // All attributes become turned off
    bold = 1, // Bold or increased intensity, // As with faint, the color change is a PC (SCO / CGA) invention.[26][better source needed]
    faint = 2, // Faint, decreased intensity, or dim, // May be implemented as a light font weight like bold.[27]
    italic = 3, // Italic, // Not widely supported. Sometimes treated as inverse or blink.[26]
    underline = 4, // Underline, // Style extensions exist for Kitty, VTE, mintty, iTerm2 and Konsole.[28][29][30]
    slow_blink = 5, // Slow blink, // Sets blinking to less than 150 times per minute
    rapid_blink = 6, // Rapid blink, // MS-DOS ANSI.SYS, 150+ per minute; not widely supported
    reverse = 7, // Reverse video or invert, // Swap foreground and background colors; inconsistent emulation[31][dubious – discuss]
    conceal = 8, // Conceal or hide, // Not widely supported.
    strike = 9, // Crossed-out, or strike, // Characters legible but marked as if for deletion. Not supported in Terminal.app.

    // Alternative font, // Select alternative font n − 10
    primary_font = 10, // Primary (default) font,
    alt_font1 = 11,
    alt_font2 = 12,
    alt_font3 = 13,
    alt_font4 = 14,
    alt_font5 = 15,
    alt_font6 = 16,
    alt_font7 = 17,
    alt_font8 = 18,
    alt_font9 = 19,

    fraktur = 20, // Fraktur (Gothic), // Rarely supported
    doubly_underlined = 21, // Doubly underlined; or: not bold, // Double-underline per ECMA-48,[16]: 8.3.117  but instead disables bold intensity on several terminals, including in the Linux kernel's console before version 4.17.[32]
    reset_intensity = 22, // Normal intensity, // Neither bold nor faint; color changes where intensity is implemented as such.
    reset_weight = 23, // Neither italic, nor blackletter
    reset_underlined = 24, // Not underlined, // Neither singly nor doubly underlined
    reset_blink = 25, // Not blinking, // Turn blinking off
    proportional_spacing = 26, // Proportional spacing, // ITU T.61 and T.416, not known to be used on terminals
    reset_reverse = 27, // Not reversed
    reset_conceal = 28, // Reveal, // Not concealed
    reset_strike = 29, // Not crossed out

    // Set foreground color
    fg_black = 30,
    fg_red = 31,
    fg_green = 32,
    fg_yellow = 33,
    fg_blue = 34,
    fg_magenta = 35,
    fg_cyan = 36,
    fg_white = 37,

    // TODO: 38, // Set foreground color, // Next arguments are 5;n or 2;r;g;b
    // TODO: 39, // Default foreground color, // Implementation defined (according to standard)

    // Set background color

    bg_black = 40,
    bg_red = 41,
    bg_green = 42,
    bg_yellow = 43,
    bg_blue = 44,
    bg_magenta = 45,
    bg_cyan = 46,
    bg_white = 47,

    // TODO: 48, // Set background color, // Next arguments are 5;n or 2;r;g;b
    // TODO: 49, // Default background color, // Implementation defined (according to standard)

    reset_proportional_spacing = 50, // Disable proportional spacing, // T.61 and T.416
    framed = 51, // Framed, // Implemented as "emoji variation selector" in mintty.[33]
    encircled = 52, // Encircled
    overlined = 53, // Overlined, // Not supported in Terminal.app
    reset_framed = 54, // Neither framed nor encircled
    reset_overlined = 55, // Not overlined

    // TODO: 58, // Set underline color, // Not in standard; implemented in Kitty, VTE, mintty, and iTerm2.[28][29] Next arguments are 5;n or 2;r;g;b.
    // TODO: 59, // Default underline color, // Not in standard; implemented in Kitty, VTE, mintty, and iTerm2.[28][29]

    // 60, // Ideogram underline or right side line, // Rarely supported
    // 61, // Ideogram double underline, or double line on the right side
    // 62, // Ideogram overline or left side line
    // 63, // Ideogram double overline, or double line on the left side
    // 64, // Ideogram stress marking
    reset_ideogram = 65, // No ideogram attributes, // Reset the effects of all of 60–64

    superscript = 73, // Superscript, // Implemented only in mintty[33]
    subscript = 74, // Subscript
    reset_script = 75, // Neither superscript nor subscript

    // Set bright foreground color,
    fg_gray = 90,
    fg_bright_red = 91,
    fg_bright_green = 92,
    fg_bright_yellow = 93,
    fg_bright_blue = 94,
    fg_bright_magenta = 95,
    fg_bright_cyan = 96,
    fg_bright_white = 97,

    // Set bright background color
    bg_gray = 100,
    bg_bright_red = 101,
    bg_bright_green = 102,
    bg_bright_yellow = 103,
    bg_bright_blue = 104,
    bg_bright_magenta = 105,
    bg_bright_cyan = 106,
    bg_bright_white = 107,
};
