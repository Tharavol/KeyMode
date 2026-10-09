-- KeyModeProbe.lua
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The throwaway addon `/km debug probe` toggles (#6). Copy this folder into
-- Interface\AddOns next to KeyMode; never shipped (.pkgmeta ignores tests/). The one
-- chat line it prints after a reload is the ground truth for "did the enable state the
-- probe set actually take effect". `## Dependencies: keymode` is deliberately lowercase,
-- so the probe can show which case GetAddOnDependencies hands back.

DEFAULT_CHAT_FRAME:AddMessage("|cffffd200KeyModeProbe|r: loaded")
