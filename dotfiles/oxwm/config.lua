---@meta
-------------------------------------------------------------------------------
-- OXWM Configuration File
-------------------------------------------------------------------------------

---Load type definitions for LSP
---@module 'oxwm'

-------------------------------------------------------------------------------
-- Variables
-------------------------------------------------------------------------------
-- Define your variables here for easy customization throughout the config.
-- This makes it simple to change keybindings, colors, and settings in one place.

-- Modifier key: "Mod4" is the Super/Windows key, "Mod1" is Alt
local modkey = "Mod4"

-- Terminal emulator command (defualts to alacritty)
local terminal = "st"

-- Color palette - customize these to match your theme
-- Alternatively you can import other files in here, such as
-- local colors = require("colors.lua") and make colors.lua a file
-- in the ~/.config/oxwm directory
-- local colors = require("tokyonight");
local theme_names = { tokyonight = true, gruvbox = true, catppuccin = true }
local theme = "tokyonight"
local theme_file = io.open(os.getenv("HOME") .. "/.config/oxwm/theme", "r")
if theme_file then
  local wanted = (theme_file:read("*l") or ""):match("^%s*(.-)%s*$")
  theme_file:close()
  if theme_names[wanted] then theme = wanted end
end
local colors = require("colors." .. theme);

local tags = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
-- local tags = { "", "󰊯", "", "󰰏", "󰟿", "󱇤", "", "󱘶", "󰧮" } -- Example of nerd font icon tags

local bar_font = "JetBrainsMono Nerd Font Propo:style=Bold:size=10"

local blocks = {
    oxwm.bar.block.ram({
        format = "Ram: {used}/{total} GB",
        interval = 5,
        color = colors.purple,
        underline = true,
        click = { command = "st -e btop", floating = true },
    }),
    oxwm.bar.block.static({
        text = "│",
        interval = 999999999,
        color = colors.sep,
        underline = false,
    }),
    oxwm.bar.block.shell({
        format = "{}",
        command = "$HOME/.config/oxwm/cpu-status.sh",
        interval = 5,
        color = colors.orange,
        underline = true,
        click = { command = "st -e btop", floating = true },
    }),
    oxwm.bar.block.static({
        text = "│",
        interval = 999999999,
        color = colors.sep,
        underline = false,
    }),
    oxwm.bar.block.shell({
        format = "{}",
        command = "$HOME/.config/oxwm/temp-status.sh",
        interval = 30,
        color = colors.red,
        underline = true,
        click = { command = "st -e btop", floating = true },
    }),
    oxwm.bar.block.static({
        text = "│",
        interval = 999999999,
        color = colors.sep,
        underline = false,
    }),
    oxwm.bar.block.shell({
        format = "{}",
        command = "$HOME/.config/oxwm/wifi-status.sh",
        interval = 10,
        color = colors.yellow,
        underline = true,
        click = { command = "st -e nmtui", floating = true },
    }),
    oxwm.bar.block.static({
        text = "│",
        interval = 999999999,
        color = colors.sep,
        underline = false,
    }),
    oxwm.bar.block.shell({
        format = "{}",
        command = "$HOME/.config/oxwm/bluetooth-status.sh",
        interval = 10,
        color = colors.light_blue,
        underline = true,
        click = { command = "st -e bluetui", floating = true },
    }),
    oxwm.bar.block.static({
        text = "│",
        interval = 999999999,
        color = colors.sep,
        underline = false,
    }),
    oxwm.bar.block.battery({
        format = "Bat: {}%",
        charging = "Chg: {}%",
        discharging = "Bat: {}%",
        full = "Full",
        interval = 30,
        color = colors.green,
        underline = true,
        click = { command = [[sh -c 'prof=$(printf power-saver\\nbalanced\\nperformance\\n | dmenu-themed -l 3) && [ -n "$prof" ] && powerprofilesctl set $prof && notify-send -h string:x-dunst-stack-tag:osd Power $prof']], floating = true },
    }),
    oxwm.bar.block.static({
        text = "│",
        interval = 999999999,
        color = colors.sep,
        underline = false,
    }),
    oxwm.bar.block.datetime({
        format = "{}",
        date_format = "%a, %b %d - %H:%M",
        interval = 30,
        color = colors.cyan,
        underline = true,
        click = { command = "st -e ikhal", floating = true },
    }),
};


-------------------------------------------------------------------------------
-- Basic Settings
-------------------------------------------------------------------------------
oxwm.set_terminal(terminal)
oxwm.set_modkey(modkey)
oxwm.set_tags(tags)

-------------------------------------------------------------------------------
-- Layouts
-------------------------------------------------------------------------------
oxwm.set_layout_symbol("tiling", "[T]")
oxwm.set_layout_symbol("normie", "[F]")
oxwm.set_layout_symbol("tabbed", "[=]")

-------------------------------------------------------------------------------
-- Appearance
-------------------------------------------------------------------------------
oxwm.border.set_width(2)
local focus_colors = { tokyonight = colors.blue, gruvbox = colors.orange, catppuccin = colors.purple }
oxwm.border.set_focused_color(focus_colors[theme] or colors.purple)
oxwm.border.set_unfocused_color(colors.grey)

-- Smart Enabled = No border if 1 window
oxwm.gaps.set_smart(false)
-- Inner gaps (horizontal, vertical) in pixels
oxwm.gaps.set_inner(5, 5)
-- Outer gaps (horizontal, vertical) in pixels
oxwm.gaps.set_outer(5, 5)

-------------------------------------------------------------------------------
-- Window Rules
-------------------------------------------------------------------------------
-- Rules allow you to automatically configure windows based on their properties
-- You can match windows by class, instance, title, or role
-- Available properties: floating, tag, fullscreen, etc.
--
-- Common use cases:
-- - Force floating for certain applications (dialogs, utilities)
-- - Send specific applications to specific workspaces
-- - Configure window behavior based on title or class

-- Examples (uncomment to use):
-- oxwm.rule.add({ instance = "gimp", floating = true })
oxwm.rule.add({ instance = "wiremix", floating = true })
-- oxwm.rule.add({ instance = "brave-browser", tag = 2 })
-- oxwm.rule.add({ class = "firefox", tag = 3 })
-- oxwm.rule.add({ instance = "slack", tag = 4 })
-- oxwm.rule.add({ instance = "discord", tag = 5 })

-- To find window properties, use xprop and click on the window
-- WM_CLASS(STRING) shows both instance and class (instance, class)

-------------------------------------------------------------------------------
-- Status Bar Configuration
-------------------------------------------------------------------------------
-- Font configuration
oxwm.bar.set_font(bar_font)

-- Set your blocks here (defined above)
oxwm.bar.set_blocks(blocks)

-- Bar color schemes (for workspace tag display)
-- Parameters: foreground, background, border

-- Unoccupied tags
oxwm.bar.set_scheme_normal(colors.fg, colors.bg, "#444444")
-- Occupied tags
oxwm.bar.set_scheme_occupied(colors.orange, colors.bg, colors.orange)
-- Currently selected tag
oxwm.bar.set_scheme_selected(colors.blue, colors.bg, colors.purple)

-------------------------------------------------------------------------------
-- Keybindings
-------------------------------------------------------------------------------
-- Basic window management

oxwm.key.bind({ modkey }, "Return", oxwm.spawn_terminal())
-- Launch Dmenu
-- oxwm.key.bind({ modkey }, "D", oxwm.spawn({ "sh", "-c", "dmenu_run -l 10" }))
oxwm.key.bind({ modkey }, "D", oxwm.spawn({ "sh", "-c", "dmenu_run -l 10" }))
-- Launch browser
 oxwm.key.bind({ modkey }, "B", oxwm.spawn({ "sh", "-c", "firefox" }))
-- Apps (terminal)
oxwm.key.bind({ modkey }, "E", oxwm.spawn({ "sh", "-c", "st -e yazi" }))
oxwm.key.bind({ modkey }, "O", oxwm.spawn({ "sh", "-c", "ocr-copy" }))
oxwm.key.bind({ modkey }, "W", oxwm.spawn({ "sh", "-c", "st -e nmtui" }))
oxwm.key.bind({ modkey }, "U", oxwm.spawn({ "sh", "-c", "st -e bluetui" }))
oxwm.key.bind({ modkey }, "Y", oxwm.spawn({ "sh", "-c", "st -e ikhal" }))
oxwm.key.bind({ modkey, "Shift" }, "B", oxwm.spawn({ "sh", "-c", "st -e btop" }))
oxwm.key.bind({ modkey }, "V", oxwm.spawn({ "sh", "-c", [[CM_LAUNCHER=dmenu-themed CM_DIR=~/.cache/clipmenu clipmenu -l 10]] }))
-- Copy screenshot to clipboard
oxwm.key.bind({ modkey }, "S", oxwm.spawn({ "sh", "-c", [[mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/$(date +%Y%m%d-%H%M%S).png && maim -s $f && xclip -selection clipboard -t image/png < $f && notify-send "Screenshot saved" "$f"]] }))
oxwm.key.bind({ modkey }, "Q", oxwm.client.kill())

-- Keybind overlay - Shows important keybindings on screen
oxwm.key.bind({ modkey, "Shift" }, "Slash", oxwm.show_keybinds())

-- Window state toggles
oxwm.key.bind({ modkey, "Shift" }, "F", oxwm.client.toggle_fullscreen())
oxwm.key.bind({ modkey, "Shift" }, "Space", oxwm.client.toggle_floating())

-- Layout management
oxwm.key.bind({ modkey }, "C", oxwm.layout.set("tiling"))
-- Cycle through layouts
oxwm.key.bind({ modkey }, "N", oxwm.layout.cycle())

-- Master area controls (tiling layout)

-- Decrease/Increase master area width
oxwm.key.bind({ modkey }, "H", oxwm.set_master_factor(-5))
oxwm.key.bind({ modkey }, "L", oxwm.set_master_factor(5))
-- Increment/Decrement number of master windows
oxwm.key.bind({ modkey }, "I", oxwm.inc_num_master(1))
oxwm.key.bind({ modkey }, "P", oxwm.inc_num_master(-1))

-- Gaps toggle
oxwm.key.bind({ modkey }, "A", oxwm.toggle_gaps())

-- Window manager controls
          oxwm.key.bind({ modkey, "Shift" }, "Q", oxwm.quit())
          oxwm.key.bind({}, "XF86AudioRaiseVolume", oxwm.spawn({ "sh", "-c", [[wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ && notify-send -h string:x-dunst-stack-tag:osd "Volume" "$($HOME/.config/oxwm/volume-status.sh)"]] }))
          oxwm.key.bind({}, "XF86AudioLowerVolume", oxwm.spawn({ "sh", "-c", [[wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && notify-send -h string:x-dunst-stack-tag:osd "Volume" "$($HOME/.config/oxwm/volume-status.sh)"]] }))
          oxwm.key.bind({}, "XF86AudioMute", oxwm.spawn({ "sh", "-c", [[wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && notify-send -h string:x-dunst-stack-tag:osd "Volume" "$($HOME/.config/oxwm/volume-status.sh)"]] }))
oxwm.key.bind({}, "XF86MonBrightnessUp", oxwm.spawn({ "sh", "-c", [[brightnessctl set 5%+ && notify-send -h string:x-dunst-stack-tag:osd "Brightness" "$($HOME/.config/oxwm/brightness-status.sh)"]] }))
oxwm.key.bind({}, "XF86MonBrightnessDown", oxwm.spawn({ "sh", "-c", [[brightnessctl set 5%- && notify-send -h string:x-dunst-stack-tag:osd "Brightness" "$($HOME/.config/oxwm/brightness-status.sh)"]] }))
oxwm.key.bind({ modkey }, "M", oxwm.spawn({ "sh", "-c", [[wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && notify-send -h string:x-dunst-stack-tag:osd "Mic" "$($HOME/.config/oxwm/mic-status.sh)"]] }))
oxwm.key.bind({ modkey, "Shift" }, "V", oxwm.spawn({ "sh", "-c", [[st -n wiremix -c wiremix -e wiremix]] }))
oxwm.key.bind({ modkey, "Shift" }, "P", oxwm.spawn({ "sh", "-c", [[prof=$({ echo power-saver; echo balanced; echo performance; } | dmenu-themed -l 3) && [ -n "$prof" ] && powerprofilesctl set $prof && notify-send -h string:x-dunst-stack-tag:osd Power $prof]] }))
oxwm.key.bind({ modkey }, "Escape", oxwm.spawn({ "sh", "-c", [[prof=$(printf 'Power off\nReboot\nSuspend\nLog out\n' | dmenu-themed -l 4) && case "$prof" in "Power off") systemctl poweroff ;; Reboot) systemctl reboot ;; Suspend) systemctl suspend ;; "Log out") pkill -x oxwm ;; esac]] }))
oxwm.key.bind({ modkey, "Shift" }, "R", oxwm.restart())

-- Focus movement [1 for up in the stack, -1 for down]
oxwm.key.bind({ modkey }, "J", oxwm.client.focus_stack(1))
oxwm.key.bind({ modkey }, "K", oxwm.client.focus_stack(-1))

-- Window movement (swap position in stack)
oxwm.key.bind({ modkey, "Shift" }, "J", oxwm.client.move_stack(1))
oxwm.key.bind({ modkey, "Shift" }, "K", oxwm.client.move_stack(-1))

-- Multi-monitor support

-- Focus next/previous Monitors
oxwm.key.bind({ modkey }, "Comma", oxwm.monitor.focus(-1))
oxwm.key.bind({ modkey }, "Period", oxwm.monitor.focus(1))
-- Move window to next/previous Monitors
oxwm.key.bind({ modkey, "Shift" }, "Comma", oxwm.monitor.tag(-1))
oxwm.key.bind({ modkey, "Shift" }, "Period", oxwm.monitor.tag(1))

-- Workspace (tag) navigation
-- Switch to workspace N (tags are 0-indexed, so tag "1" is index 0)
oxwm.key.bind({ modkey }, "1", oxwm.tag.view(0))
oxwm.key.bind({ modkey }, "2", oxwm.tag.view(1))
oxwm.key.bind({ modkey }, "3", oxwm.tag.view(2))
oxwm.key.bind({ modkey }, "4", oxwm.tag.view(3))
oxwm.key.bind({ modkey }, "5", oxwm.tag.view(4))
oxwm.key.bind({ modkey }, "6", oxwm.tag.view(5))
oxwm.key.bind({ modkey }, "7", oxwm.tag.view(6))
oxwm.key.bind({ modkey }, "8", oxwm.tag.view(7))
oxwm.key.bind({ modkey }, "9", oxwm.tag.view(8))

-- Move focused window to workspace N
oxwm.key.bind({ modkey, "Shift" }, "1", oxwm.tag.move_to(0))
oxwm.key.bind({ modkey, "Shift" }, "2", oxwm.tag.move_to(1))
oxwm.key.bind({ modkey, "Shift" }, "3", oxwm.tag.move_to(2))
oxwm.key.bind({ modkey, "Shift" }, "4", oxwm.tag.move_to(3))
oxwm.key.bind({ modkey, "Shift" }, "5", oxwm.tag.move_to(4))
oxwm.key.bind({ modkey, "Shift" }, "6", oxwm.tag.move_to(5))
oxwm.key.bind({ modkey, "Shift" }, "7", oxwm.tag.move_to(6))
oxwm.key.bind({ modkey, "Shift" }, "8", oxwm.tag.move_to(7))
oxwm.key.bind({ modkey, "Shift" }, "9", oxwm.tag.move_to(8))

-- Combo view (view multiple tags at once) {argos_nothing}
-- Example: Mod+Ctrl+2 while on tag 1 will show BOTH tags 1 and 2
oxwm.key.bind({ modkey, "Control" }, "1", oxwm.tag.toggleview(0))
oxwm.key.bind({ modkey, "Control" }, "2", oxwm.tag.toggleview(1))
oxwm.key.bind({ modkey, "Control" }, "3", oxwm.tag.toggleview(2))
oxwm.key.bind({ modkey, "Control" }, "4", oxwm.tag.toggleview(3))
oxwm.key.bind({ modkey, "Control" }, "5", oxwm.tag.toggleview(4))
oxwm.key.bind({ modkey, "Control" }, "6", oxwm.tag.toggleview(5))
oxwm.key.bind({ modkey, "Control" }, "7", oxwm.tag.toggleview(6))
oxwm.key.bind({ modkey, "Control" }, "8", oxwm.tag.toggleview(7))
oxwm.key.bind({ modkey, "Control" }, "9", oxwm.tag.toggleview(8))

-- Multi tag (window on multiple tags)
-- Example: Mod+Ctrl+Shift+2 puts focused window on BOTH current tag and tag 2
oxwm.key.bind({ modkey, "Control", "Shift" }, "1", oxwm.tag.toggletag(0))
oxwm.key.bind({ modkey, "Control", "Shift" }, "2", oxwm.tag.toggletag(1))
oxwm.key.bind({ modkey, "Control", "Shift" }, "3", oxwm.tag.toggletag(2))
oxwm.key.bind({ modkey, "Control", "Shift" }, "4", oxwm.tag.toggletag(3))
oxwm.key.bind({ modkey, "Control", "Shift" }, "5", oxwm.tag.toggletag(4))
oxwm.key.bind({ modkey, "Control", "Shift" }, "6", oxwm.tag.toggletag(5))
oxwm.key.bind({ modkey, "Control", "Shift" }, "7", oxwm.tag.toggletag(6))
oxwm.key.bind({ modkey, "Control", "Shift" }, "8", oxwm.tag.toggletag(7))
oxwm.key.bind({ modkey, "Control", "Shift" }, "9", oxwm.tag.toggletag(8))

-------------------------------------------------------------------------------
-- Advanced: Keychords
-------------------------------------------------------------------------------
-- Keychords allow you to bind multiple-key sequences (like Emacs or Vim)
-- Format: {{modifiers}, key1}, {{modifiers}, key2}, ...
-- Example: Press Mod4+Space, then release and press T to spawn a terminal
oxwm.key.chord({
    { { modkey }, "Space" },
    { {},         "T" }
}, oxwm.spawn_terminal())

oxwm.key.chord({
    { { modkey }, "F" },
    { {},         "B" }
}, oxwm.spawn({ "sh", "-c", "$HOME/repos/dmenu-scripts/bookmarks-dmenu.sh" }))

oxwm.key.chord({
    { { modkey }, "F" },
    { {},         "F" }
}, oxwm.spawn({ "sh", "-c", "$HOME/repos/dmenu-scripts/repos-dmenu.sh" }))

oxwm.key.chord({
    { { modkey }, "F" },
    { {},         "O" }
}, oxwm.spawn({ "sh", "-c", "$HOME/repos/dmenu-scripts/tmux-dmenu.sh" }))

-------------------------------------------------------------------------------
-- Autostart
-------------------------------------------------------------------------------
-- Commands to run once when OXWM starts
-- Uncomment and modify these examples, or add your own

-- oxwm.autostart("picom")
          -- oxwm.autostart("xwallpaper --zoom ~/walls/dune.jpg")
local hp_wallpapers = {
  tokyonight = os.getenv("HOME") .. "/.config/oxwm/wallpapers/tokyonight.jpg",
  gruvbox = os.getenv("HOME") .. "/.config/oxwm/wallpapers/gruvbox.png",
  catppuccin = os.getenv("HOME") .. "/.config/oxwm/wallpapers/catppuccin.jpg",
}
oxwm.autostart("feh --bg-fill " .. hp_wallpapers[theme])
oxwm.autostart("dunst")
-- clipmenud runs as a systemd user service below, so WM reloads
-- can't orphan it the way autostart children get orphaned.
-- oxwm.autostart("nm-applet")
