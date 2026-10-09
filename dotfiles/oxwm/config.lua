-- OXWM default config — wm-installer (Arch Linux)
-- Disalin ke ~/.config/oxwm/config.lua bila belum ada.
-- Reload: Mod4+Shift+R. Referensi: https://github.com/tonybanters/oxwm

-- Gaps
oxwm.gaps.set_enabled(true)
oxwm.gaps.set_inner(8, 8)
oxwm.gaps.set_outer(8, 8)

-- Terminal & modkey
local term = "alacritty"
local mod = "Mod4"

-- Keybindings dasar (gaya dwm)
oxwm.key.bind({ mod }, "Return", oxwm.spawn(term))
oxwm.key.bind({ mod }, "d", oxwm.spawn("rofi -show drun"))
oxwm.key.bind({ mod }, "Q", oxwm.client.kill())
oxwm.key.bind({ mod, "Shift" }, "Q", oxwm.quit())
oxwm.key.bind({ mod, "Shift" }, "R", oxwm.reload())

-- Fokus & pindah jendela
oxwm.key.bind({ mod }, "h", oxwm.focus.left())
oxwm.key.bind({ mod }, "j", oxwm.focus.down())
oxwm.key.bind({ mod }, "k", oxwm.focus.up())
oxwm.key.bind({ mod }, "l", oxwm.focus.right())

-- Tags 1-9
for i = 1, 9 do
  oxwm.key.bind({ mod }, tostring(i), oxwm.tag.view(i))
  oxwm.key.bind({ mod, "Shift" }, tostring(i), oxwm.tag.move(i))
end

-- Autostart
oxwm.autostart({ "picom", "feh --bg-fill ~/.wallpaper.png" })
