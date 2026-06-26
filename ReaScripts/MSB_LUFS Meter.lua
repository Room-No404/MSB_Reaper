-- @description MSB_LUFS Meter
-- @author Minseok Bang
-- @requires ReaImGui v1.0.0

local CONFIG = {
    WIN_W      = 550,           -- Window base width
    WIN_H      = 150,           -- Window base height
    PAD_X      = 10,            -- Window inner horizontal padding
    PAD_Y      = 2,             -- Window inner vertical padding

    FNT_FAMILY = 'sans-serif',  -- Base font family
    FNT_LBL    = 14,            -- Label font size
    FNT_UNIT   = 14,            -- Unit font size
    FNT_TOP    = 30,            -- Top row main number font size
    FNT_BTM    = 15,            -- Bottom row sub number font size

    GAP_ROW    = -6,            -- Vertical gap between top and bottom rows
    GAP_COL_V  = -6,            -- Vertical gap between label and value (Top row)
    GAP_COL_H1 = 8,             -- Horizontal gap between label and value (Bottom row)
    GAP_COL_H2 = 6,             -- Horizontal gap between value and unit

    C_BG       = 0x111215FF,    -- Background color
    C_LBL      = 0x999999FF,    -- Label text color
    C_UNIT     = 0x666666FF,    -- Unit text color
    C_VAL      = 0xEEEEEEFF,    -- Default value text color
    C_GREEN    = 0x2ECC71FF,    -- Safe status color (Green)
    C_YELL     = 0xFFA502FF,    -- Warning status color (Yellow)
    C_RED      = 0xFF4757FF,    -- Alert status color (Red)
}

local PRESETS = {
    { name = "BS.1770-4 Standard",   int = -24.0, tp = -2.0 },
    { name = "EBU R128 Standard",    int = -23.0, tp = -1.0 },
    { name = "YouTube / Music",      int = -14.0, tp = -1.0 },
    { name = "ASWG Home (Sony)",     int = -24.0, tp = -2.0 },
    { name = "ASWG Portable (Sony)", int = -18.0, tp = -1.0 }
}

reaper.gmem_attach('MSB_LUFS_Shared')
local ctx = reaper.ImGui_CreateContext('MSB_LUFS Meter')
local f_sans = reaper.ImGui_CreateFont(CONFIG.FNT_FAMILY)
reaper.ImGui_Attach(ctx, f_sans)

local sel_idx = 3
local settings = { target_int = PRESETS[sel_idx].int, target_tp = PRESETS[sel_idx].tp }
local last_vals = { M = -145, S = -145, I = -145, L = 0, P = -145 }

local function getTextSize(text, size)
    reaper.ImGui_PushFont(ctx, f_sans, size)
    local w, h = reaper.ImGui_CalcTextSize(ctx, text)
    reaper.ImGui_PopFont(ctx)
    return w, h
end

local function draw_metric(label, val, unit, font_size, metric_type)
    reaper.ImGui_BeginGroup(ctx)
    local avail_w, start_x = reaper.ImGui_GetContentRegionAvail(ctx), reaper.ImGui_GetCursorPosX(ctx)
    local lw = getTextSize(label, CONFIG.FNT_LBL)
    reaper.ImGui_SetCursorPosX(ctx, start_x + (avail_w - lw) * 0.5)
    reaper.ImGui_PushFont(ctx, f_sans, CONFIG.FNT_LBL); reaper.ImGui_TextColored(ctx, CONFIG.C_LBL, label); reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + CONFIG.GAP_COL_V)

    local val_str = (val <= -145) and "-Inf" or string.format("%.1f", val)
    local col = CONFIG.C_GREEN

    if metric_type == "I" then
        if val > settings.target_int then col = CONFIG.C_RED
        elseif val >= (settings.target_int - 2.0) then col = CONFIG.C_YELL
        else col = CONFIG.C_GREEN end
    else
        local red_threshold = (settings.target_int == -14.0) and 6.0 or 8.0
        if val > settings.target_int + red_threshold then col = CONFIG.C_RED
        elseif val >= settings.target_int + 4.0 then col = CONFIG.C_YELL
        else col = CONFIG.C_GREEN end
    end

    local vw, vh = getTextSize(val_str, font_size)
    local uw, uh = getTextSize(unit, CONFIG.FNT_UNIT)
    reaper.ImGui_SetCursorPosX(ctx, start_x + (avail_w - (vw + CONFIG.GAP_COL_H2 + uw)) * 0.5)
    local cur_y = reaper.ImGui_GetCursorPosY(ctx)
    reaper.ImGui_PushFont(ctx, f_sans, font_size); reaper.ImGui_TextColored(ctx, col, val_str); reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SameLine(ctx, nil, CONFIG.GAP_COL_H2)
    reaper.ImGui_SetCursorPosY(ctx, cur_y + vh - uh - 4)
    reaper.ImGui_PushFont(ctx, f_sans, CONFIG.FNT_UNIT); reaper.ImGui_TextColored(ctx, CONFIG.C_UNIT, unit); reaper.ImGui_PopFont(ctx)
    reaper.ImGui_EndGroup(ctx)
end

local function draw_metric_horizontal(label, val, unit, font_size)
    reaper.ImGui_BeginGroup(ctx)
    local avail_w, start_x = reaper.ImGui_GetContentRegionAvail(ctx), reaper.ImGui_GetCursorPosX(ctx)
    local val_str, col = (val <= -145) and "-Inf" or string.format("%.1f", val), CONFIG.C_VAL

    if label == "True Peak" then
        if val > settings.target_tp then col = CONFIG.C_RED
        elseif val >= settings.target_tp - 1.0 then col = CONFIG.C_YELL end
    end

    local lw, vw, uw = getTextSize(label, CONFIG.FNT_LBL), getTextSize(val_str, font_size), getTextSize(unit, CONFIG.FNT_UNIT)
    reaper.ImGui_SetCursorPosX(ctx, start_x + (avail_w - (lw + CONFIG.GAP_COL_H1 + vw + CONFIG.GAP_COL_H2 + uw)) * 0.5)
    reaper.ImGui_PushFont(ctx, f_sans, CONFIG.FNT_LBL); reaper.ImGui_TextColored(ctx, CONFIG.C_LBL, label); reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SameLine(ctx, nil, CONFIG.GAP_COL_H1)
    reaper.ImGui_PushFont(ctx, f_sans, font_size); reaper.ImGui_TextColored(ctx, col, val_str); reaper.ImGui_PopFont(ctx)
    reaper.ImGui_SameLine(ctx, nil, CONFIG.GAP_COL_H2)
    reaper.ImGui_PushFont(ctx, f_sans, CONFIG.FNT_UNIT); reaper.ImGui_TextColored(ctx, CONFIG.C_UNIT, unit); reaper.ImGui_PopFont(ctx)
    reaper.ImGui_EndGroup(ctx)
end

local function loop()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), CONFIG.C_BG)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), CONFIG.PAD_X, CONFIG.PAD_Y)
    reaper.ImGui_SetNextWindowSize(ctx, CONFIG.WIN_W, CONFIG.WIN_H, reaper.ImGui_Cond_FirstUseEver())
    local vis, open = reaper.ImGui_Begin(ctx, 'MSB_LUFS Meter', true, reaper.ImGui_WindowFlags_NoScrollbar())

    if vis then
        local m = reaper.gmem_read(0)
        local s = reaper.gmem_read(1)
        local i = reaper.gmem_read(2)
        local l = reaper.gmem_read(3)
        local p = reaper.gmem_read(4)
        local play_state = reaper.gmem_read(5)

        if play_state == 1 or play_state == 2 then
            last_vals.M = m
            last_vals.S = s
            last_vals.I = i
            last_vals.L = l
            last_vals.P = p
        end

        if i <= -145 then
            last_vals = { M = -145, S = -145, I = -145, L = 0, P = -145 }
        end

        if reaper.ImGui_BeginTable(ctx, "t", 3, reaper.ImGui_TableFlags_SizingStretchSame()) then
            reaper.ImGui_TableNextColumn(ctx); draw_metric("Short Term", last_vals.S, "LUFS", CONFIG.FNT_TOP, "S")
            reaper.ImGui_TableNextColumn(ctx); draw_metric("Integrated", last_vals.I, "LUFS", CONFIG.FNT_TOP, "I")
            reaper.ImGui_TableNextColumn(ctx); draw_metric("Momentary Max", last_vals.M, "LUFS", CONFIG.FNT_TOP, "M")
            reaper.ImGui_EndTable(ctx)
        end
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + CONFIG.GAP_ROW)

        if reaper.ImGui_BeginTable(ctx, "b", 3, reaper.ImGui_TableFlags_SizingStretchSame()) then
            reaper.ImGui_TableNextColumn(ctx); draw_metric_horizontal("LRA", last_vals.L, "LU", CONFIG.FNT_BTM)
            reaper.ImGui_TableNextColumn(ctx); draw_metric_horizontal("True Peak", last_vals.P, "dB", CONFIG.FNT_BTM)
            reaper.ImGui_TableNextColumn(ctx)
            local av, cb = reaper.ImGui_GetContentRegionAvail(ctx), reaper.ImGui_GetContentRegionAvail(ctx) * 0.85
            reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + (av - cb) * 0.5)
            reaper.ImGui_SetNextItemWidth(ctx, cb)
            reaper.ImGui_PushFont(ctx, f_sans, CONFIG.FNT_LBL)
            if reaper.ImGui_BeginCombo(ctx, "##T", PRESETS[sel_idx].name) then
                for idx, d in ipairs(PRESETS) do
                    if reaper.ImGui_Selectable(ctx, d.name, sel_idx == idx) then
                        sel_idx = idx
                        settings.target_int, settings.target_tp = d.int, d.tp
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end
            reaper.ImGui_PopFont(ctx); reaper.ImGui_EndTable(ctx)
        end
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx, 1); reaper.ImGui_PopStyleColor(ctx, 1)
    if open then reaper.defer(loop) end
end
reaper.defer(loop)

