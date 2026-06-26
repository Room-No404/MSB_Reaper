-- @description MSB_Mini Item Properites
-- @version 0.9.0
-- @author Minseok Bang
-- @requires ReaImGui (ReaPack)

-- =====================
-- Helpers
-- =====================
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round(x)
  if x >= 0 then return math.floor(x + 0.5) end
  return math.ceil(x - 0.5)
end

local function amp_to_db(amp)
  if amp <= 0 then return -150.0 end
  return 20.0 * (math.log(amp, 10))
end

local function db_to_amp(db)
  return 10.0 ^ (db / 20.0)
end

local function parse_pan(str)
  if not str then return nil end
  str = str:upper()
  if str == "C" then return 0.0 end
  local num = string.match(str, "%d+")
  if not num then return nil end
  num = tonumber(num)
  local has_L = string.find(str, "L") ~= nil
  local has_R = string.find(str, "R") ~= nil
  local has_neg = string.find(str, "-") ~= nil
  if has_R then
    num = math.abs(num)
  elseif has_L or has_neg then
    num = -math.abs(num)
  end
  return clamp(num, -100, 100) / 100.0
end

local function pan_to_str(pan)
  local p = round(pan * 100)
  if p < 0 then return tostring(math.abs(p)) .. "L"
  elseif p > 0 then return tostring(p) .. "R"
  else return "C" end
end

local function split_pitch(st)
  local x = st * 100
  local p100
  if x >= 0 then p100 = math.floor(x + 0.5) else p100 = math.ceil(x - 0.5) end
  local sem
  if p100 >= 0 then sem = math.floor(p100 / 100) else sem = math.ceil(p100 / 100) end
  local cent = p100 - sem * 100

  if cent >= 50 then
    cent = cent - 100
    sem  = sem + 1
  elseif cent < -50 then
    cent = cent + 100
    sem  = sem - 1
  end

  sem  = clamp(sem,  -96, 96)
  cent = clamp(cent, -50, 49)
  return sem, cent
end

local function join_pitch(sem, cent)
  cent = clamp(cent, -50, 49)
  return sem + (cent / 100.0)
end

local function begin_undo()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
end

local function end_undo(name)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(name, -1)
end

local function get_selected_item()
  return reaper.GetSelectedMediaItem(0, 0)
end

local function for_each_selected_item(fn)
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then fn(it) end
  end
end

-- =====================
-- ImGui init
-- =====================
local ctx = reaper.ImGui_CreateContext('MSB_Mini Item Properites')
reaper.ImGui_SetNextWindowSize(ctx, 520, 78, reaper.ImGui_Cond_FirstUseEver())

-- =====================
-- Theme
-- =====================
local function col(r, g, b, a)
  local cr, cg, cb, ca = r/255, g/255, b/255, (a or 255)/255
  return reaper.ImGui_ColorConvertDouble4ToU32(cr, cg, cb, ca)
end

local function push_theme()
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),        col(50,50,50,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),          col(80,80,80,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),            col(245,245,245,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextDisabled(),    col(170,170,170,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),         col(10,10,10,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),  col(18,18,18,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),   col(24,24,24,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),   col(70,70,70,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(),    col(85,85,85,255))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(),         col(30,30,30,255))

  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 12, 10)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(),  8, 4)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),   8, 4)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(),4)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(),1)
end

local function pop_theme()
  reaper.ImGui_PopStyleVar(ctx, 6)
  reaper.ImGui_PopStyleColor(ctx, 10)
end

-- =====================
-- Layout constants
-- =====================
local BOX_W            = 42
local LABEL_W          = 32
local GAP_AFTER_BOX    = 10
local FADE_BOX_W       = 60
local FADE_GAP         = 12
local NAME_INPUT_W     = 218
local CLEAR_BTN_W      = 20
local NAME_GAP         = 4
local LINE_GAP_Y       = 2

-- =====================
-- State
-- =====================
local function get_wheel() return reaper.ImGui_GetMouseWheel(ctx) end
local consumed_wheel = false
local scrollY_before = 0.0

local edit_field = nil
local buf = { vol = "", st = "", ct = "", pan = "" }
local focus_next = false

local function label_fixed(text, label_w)
  reaper.ImGui_AlignTextToFramePadding(ctx)
  local x0 = reaper.ImGui_GetCursorPosX(ctx)
  reaper.ImGui_Text(ctx, text)
  reaper.ImGui_SameLine(ctx, x0 + label_w)
end

-- =====================
-- Fade graphics
-- =====================
local function ease_shape(shape, t)
  if shape == 0 then return t end
  if shape == 1 then return 1 - (1 - t) ^ 2 end
  if shape == 2 then return t ^ 2 end
  if shape == 3 then return 1 - (1 - t) ^ 3 end
  if shape == 4 then return t ^ 3 end
  if shape == 5 then return t * t * (3 - 2 * t) end
  if shape == 6 then return (t < 0.5) and (2 * t * t) or (1 - 2 * (1 - t) * (1 - t)) end
  return t
end

local function draw_fade_icon_at(x, y, w, h, shape, highlighted, mirror)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local col_bg = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_FrameBg())
  local col_bd = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_Border())
  local col_ln = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_Text())
  local col_hi = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_FrameBgHovered())

  reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, (highlighted and col_hi or col_bg), 4.0)
  reaper.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, col_bd, 4.0)

  local pad = 2
  local x0, y0 = x + pad, y + h - pad
  local x1, y1 = x + w - pad, y + pad

  local last_px, last_py
  local steps = 18
  for i = 0, steps do
    local tt = i / steps
    local v = ease_shape(shape, tt)
    local ttx = mirror and (1.0 - tt) or tt
    local px = x0 + (x1 - x0) * ttx
    local py = y0 - (y0 - y1) * v
    if last_px then
      reaper.ImGui_DrawList_AddLine(dl, last_px, last_py, px, py, col_ln, 1.4)
    end
    last_px, last_py = px, py
  end
end

local NUM_SHAPES = 7

local function shape_picker(idbase, current_shape, on_change, mirror, w, h)
  local popup_id = idbase .. "_popup"
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)

  if reaper.ImGui_InvisibleButton(ctx, idbase .. "_btn", w, h) then
    reaper.ImGui_OpenPopup(ctx, popup_id)
  end
  local hovered = reaper.ImGui_IsItemHovered(ctx)

  if hovered then
    local wheel = get_wheel()
    if wheel ~= 0.0 then
      consumed_wheel = true
      local idx = current_shape
      if wheel > 0 then idx = idx - 1 else idx = idx + 1 end
      idx = clamp(idx, 0, NUM_SHAPES - 1)
      on_change(idx)
    end
  end

  draw_fade_icon_at(x, y, w, h, current_shape, hovered, mirror)

  if reaper.ImGui_BeginPopup(ctx, popup_id) then
    for sid = 0, NUM_SHAPES - 1 do
      local px, py = reaper.ImGui_GetCursorScreenPos(ctx)
      if reaper.ImGui_InvisibleButton(ctx, idbase .. "_pick_" .. sid, w, h) then
        on_change(sid)
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      local hov = reaper.ImGui_IsItemHovered(ctx)
      draw_fade_icon_at(px, py, w, h, sid, (hov or sid == current_shape), mirror)
      reaper.ImGui_Spacing(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

-- =====================
-- Centered box & inline input
-- =====================
local function draw_centered_box(id, text, w, h, custom_bg, custom_hi)
  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)

  local clicked = false
  if reaper.ImGui_InvisibleButton(ctx, id, w, h) then clicked = true end

  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local dclicked = hovered and reaper.ImGui_IsMouseDoubleClicked(ctx, 0)
  if dclicked then clicked = false end

  local col_bg = custom_bg or reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_FrameBg())
  local col_hi = custom_hi or reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_FrameBgHovered())
  local col_bd = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_Border())
  local col_tx = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_Text())

  reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, hovered and col_hi or col_bg, 4.0)
  reaper.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, col_bd, 4.0)

  local tw, th = reaper.ImGui_CalcTextSize(ctx, text)
  reaper.ImGui_DrawList_AddText(dl, x + (w - tw) * 0.5, y + (h - th) * 0.5, col_tx, text)

  return clicked, hovered, dclicked
end

local function inline_input(id, key, w)
  reaper.ImGui_PushItemWidth(ctx, w)
  if focus_next then
    reaper.ImGui_SetKeyboardFocusHere(ctx)
    focus_next = false
  end
  local flags = reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll()
  local enter, out = reaper.ImGui_InputText(ctx, id, buf[key], flags)
  if type(out) == "string" then buf[key] = out end

  local deact_edit = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
  local deact_any  = reaper.ImGui_IsItemDeactivated(ctx)
  local hovered    = reaper.ImGui_IsItemHovered(ctx)
  local active     = reaper.ImGui_IsItemActive(ctx)
  local dclicked   = hovered and reaper.ImGui_IsMouseDoubleClicked(ctx, 0)

  reaper.ImGui_PopItemWidth(ctx)
  return enter, deact_edit, deact_any, hovered, active, dclicked
end

-- =====================
-- Generic spinner box
--   opts: {
--     display     = string,
--     enabled     = bool,
--     on_wheel    = function(direction:int),  -- direction is +1 or -1
--     on_typed    = function(buf_string),
--     on_reset    = function(),
--   }
-- =====================
local function spinner_box(id, key, opts)
  local box_h = reaper.ImGui_GetFrameHeight(ctx)

  if not opts.enabled then
    draw_centered_box(id .. "_na", "-", BOX_W, box_h)
    return
  end

  if edit_field == key then
    local enter, deact_edit, deact_any, hov, active, dclicked = inline_input(id .. "_in", key, BOX_W)
    if dclicked then
      opts.on_reset()
      edit_field = nil
    elseif hov and (not active) then
      local w = get_wheel()
      if w ~= 0.0 then
        consumed_wheel = true
        opts.on_wheel(w > 0 and 1 or -1)
      end
    elseif enter or deact_edit then
      opts.on_typed(buf[key])
      edit_field = nil
    elseif deact_any then
      edit_field = nil
    end
  else
    buf[key] = opts.display
    local clicked, hov, dclicked = draw_centered_box(id .. "_box", opts.display, BOX_W, box_h)
    if dclicked then
      opts.on_reset()
    else
      if hov then
        local w = get_wheel()
        if w ~= 0.0 then
          consumed_wheel = true
          opts.on_wheel(w > 0 and 1 or -1)
        end
      end
      if clicked then edit_field = key; focus_next = true end
    end
  end
end

-- =====================
-- Main loop
-- =====================
local function loop()
  push_theme()

  local win_flags = reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse()
  local visible, open = reaper.ImGui_Begin(ctx, 'MSB_Mini Item Properites', true, win_flags)

  if visible then
    consumed_wheel = false
    scrollY_before = reaper.ImGui_GetScrollY(ctx)

    local box_h = reaper.ImGui_GetFrameHeight(ctx)

    local item = get_selected_item()
    if not item then
      reaper.ImGui_Text(ctx, 'No item selected.')
      reaper.ImGui_End(ctx)
      pop_theme()
      if open then reaper.defer(loop) end
      return
    end

    local take = reaper.GetActiveTake(item)

    local item_vol = reaper.GetMediaItemInfo_Value(item, 'D_VOL')
    local take_vol = take and reaper.GetMediaItemTakeInfo_Value(take, 'D_VOL') or 1.0
    local vol_db = amp_to_db(item_vol) + amp_to_db(take_vol)

    local pitch_st = 0.0
    if take then pitch_st = reaper.GetMediaItemTakeInfo_Value(take, 'D_PITCH') end
    local sem, cent = split_pitch(pitch_st)

    local pan_val = 0.0
    if take then pan_val = reaper.GetMediaItemTakeInfo_Value(take, 'D_PAN') end

    local fin_shape  = math.floor(reaper.GetMediaItemInfo_Value(item, 'C_FADEINSHAPE'))
    local fout_shape = math.floor(reaper.GetMediaItemInfo_Value(item, 'C_FADEOUTSHAPE'))

    -- ===== Line 1: Vol / Semi / Cent / Pan / Fade In =====
    -- Apply a dB delta to all selected items by adjusting item volume only.
    local function shift_vol_db(delta_db)
      if delta_db == 0 then return end
      begin_undo()
      for_each_selected_item(function(it)
        local cur = reaper.GetMediaItemInfo_Value(it, 'D_VOL')
        local cur_db = amp_to_db(cur)
        local new_db = clamp(cur_db + delta_db, -150.0, 24.0)
        reaper.SetMediaItemInfo_Value(it, 'D_VOL', db_to_amp(new_db))
      end)
      end_undo("Set item volume")
    end

    label_fixed("Vol", LABEL_W)
    spinner_box("##vol", "vol", {
      display = string.format("%.1f", vol_db),
      enabled = take ~= nil,
      on_wheel = function(dir) shift_vol_db(dir * 0.1) end,
      on_typed = function(s)
        local n = tonumber(s)
        if n then
          local target = clamp(n, -150.0, 24.0)
          shift_vol_db(target - vol_db)
        end
      end,
      on_reset = function()
        begin_undo()
        for_each_selected_item(function(it)
          reaper.SetMediaItemInfo_Value(it, 'D_VOL', 1.0)
          local tk = reaper.GetActiveTake(it)
          if tk then reaper.SetMediaItemTakeInfo_Value(tk, 'D_VOL', 1.0) end
        end)
        end_undo("Reset item volume")
      end,
    })

    local function shift_pitch_st(delta_st)
      if delta_st == 0 then return end
      begin_undo()
      for_each_selected_item(function(it)
        local tk = reaper.GetActiveTake(it)
        if tk then
          local cur = reaper.GetMediaItemTakeInfo_Value(tk, 'D_PITCH')
          local s, c = split_pitch(cur)
          s = clamp(s + delta_st, -96, 96)
          reaper.SetMediaItemTakeInfo_Value(tk, 'D_PITCH', join_pitch(s, c))
        end
      end)
      end_undo("Set semitone")
    end

    reaper.ImGui_SameLine(ctx, nil, GAP_AFTER_BOX)
    label_fixed("Semi", LABEL_W)
    spinner_box("##st", "st", {
      display = tostring(sem),
      enabled = take ~= nil,
      on_wheel = function(dir) shift_pitch_st(dir) end,
      on_typed = function(s)
        local n = tonumber(s)
        if n then
          local target = clamp(round(n), -96, 96)
          shift_pitch_st(target - sem)
        end
      end,
      on_reset = function()
        begin_undo()
        for_each_selected_item(function(it)
          local tk = reaper.GetActiveTake(it)
          if tk then
            local cur = reaper.GetMediaItemTakeInfo_Value(tk, 'D_PITCH')
            local _, c = split_pitch(cur)
            reaper.SetMediaItemTakeInfo_Value(tk, 'D_PITCH', join_pitch(0, c))
          end
        end)
        end_undo("Reset semitone")
      end,
    })

    -- Apply a cent delta to all items, wrapping into semitones as needed.
    local function shift_pitch_cent(delta_cent)
      if delta_cent == 0 then return end
      begin_undo()
      for_each_selected_item(function(it)
        local tk = reaper.GetActiveTake(it)
        if tk then
          local cur = reaper.GetMediaItemTakeInfo_Value(tk, 'D_PITCH')
          local s, c = split_pitch(cur)
          local total = s * 100 + c + delta_cent
          local ns = math.floor((total + 50) / 100)
          local nc = total - ns * 100
          if nc > 49 then nc = nc - 100; ns = ns + 1 end
          if nc < -50 then nc = nc + 100; ns = ns - 1 end
          ns = clamp(ns, -96, 96)
          nc = clamp(nc, -50, 49)
          reaper.SetMediaItemTakeInfo_Value(tk, 'D_PITCH', join_pitch(ns, nc))
        end
      end)
      end_undo("Set cent")
    end

    reaper.ImGui_SameLine(ctx, nil, GAP_AFTER_BOX)
    label_fixed("Cent", LABEL_W)
    spinner_box("##ct", "ct", {
      display = tostring(cent),
      enabled = take ~= nil,
      on_wheel = function(dir) shift_pitch_cent(dir) end,
      on_typed = function(s)
        local n = tonumber(s)
        if n then
          local target = round(n)
          shift_pitch_cent(target - cent)
        end
      end,
      on_reset = function()
        begin_undo()
        for_each_selected_item(function(it)
          local tk = reaper.GetActiveTake(it)
          if tk then
            local cur = reaper.GetMediaItemTakeInfo_Value(tk, 'D_PITCH')
            local s, _ = split_pitch(cur)
            reaper.SetMediaItemTakeInfo_Value(tk, 'D_PITCH', join_pitch(s, 0))
          end
        end)
        end_undo("Reset cent")
      end,
    })

    local function shift_pan(delta_p100)
      if delta_p100 == 0 then return end
      begin_undo()
      for_each_selected_item(function(it)
        local tk = reaper.GetActiveTake(it)
        if tk then
          local cur = reaper.GetMediaItemTakeInfo_Value(tk, 'D_PAN')
          local p100 = clamp(round(cur * 100) + delta_p100, -100, 100)
          reaper.SetMediaItemTakeInfo_Value(tk, 'D_PAN', p100 / 100.0)
        end
      end)
      end_undo("Set pan")
    end

    reaper.ImGui_SameLine(ctx, nil, GAP_AFTER_BOX)
    local pan_x = reaper.ImGui_GetCursorPosX(ctx)
    label_fixed("Pan", LABEL_W)
    spinner_box("##pan", "pan", {
      display = pan_to_str(pan_val),
      enabled = take ~= nil,
      on_wheel = function(dir) shift_pan(dir) end,
      on_typed = function(s)
        local parsed = parse_pan(s)
        if parsed then
          local target = round(parsed * 100)
          local cur = round(pan_val * 100)
          shift_pan(target - cur)
        end
      end,
      on_reset = function()
        begin_undo()
        for_each_selected_item(function(it)
          local tk = reaper.GetActiveTake(it)
          if tk then reaper.SetMediaItemTakeInfo_Value(tk, 'D_PAN', 0.0) end
        end)
        end_undo("Reset pan")
      end,
    })

    local fade_x = pan_x + LABEL_W + BOX_W + FADE_GAP
    reaper.ImGui_SameLine(ctx, fade_x)
    shape_picker("fin", fin_shape, function(v)
      begin_undo()
      for_each_selected_item(function(it)
        reaper.SetMediaItemInfo_Value(it, 'C_FADEINSHAPE', v)
      end)
      end_undo("Set fade-in shape")
    end, false, FADE_BOX_W, box_h)

    reaper.ImGui_Dummy(ctx, 0, LINE_GAP_Y)

    -- ===== Line 2: Take name / Clear / Reverse / Fade Out =====
    if take then
      local _, current_name = reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', '', false)
      reaper.ImGui_PushItemWidth(ctx, NAME_INPUT_W)
      local _, new_name = reaper.ImGui_InputText(ctx, '##take_name', current_name)
      reaper.ImGui_PopItemWidth(ctx)
      if reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
        reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', new_name, true)
        reaper.UpdateArrange()
      end

      reaper.ImGui_SameLine(ctx, nil, NAME_GAP)
      local color_c_bg = col(80, 30, 30, 255)
      local color_c_hi = col(110, 40, 40, 255)
      local c_clicked = draw_centered_box("##clear_name", "C", CLEAR_BTN_W, box_h, color_c_bg, color_c_hi)
      if c_clicked then
        reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME', '', true)
        reaper.UpdateArrange()
      end

      reaper.ImGui_SameLine(ctx, pan_x)
      local rev_btn_w = LABEL_W + BOX_W
      local rev_clicked = draw_centered_box("##rev_btn", "Reverse", rev_btn_w, box_h)
      if rev_clicked then
        reaper.Main_OnCommand(41051, 0)
      end

      reaper.ImGui_SameLine(ctx, fade_x)
      shape_picker("fout", fout_shape, function(v)
        begin_undo()
        for_each_selected_item(function(it)
          reaper.SetMediaItemInfo_Value(it, 'C_FADEOUTSHAPE', v)
        end)
        end_undo("Set fade-out shape")
      end, true, FADE_BOX_W, box_h)
    end

    if consumed_wheel then
      reaper.ImGui_SetScrollY(ctx, scrollY_before)
    end

    reaper.ImGui_End(ctx)
  end

  pop_theme()

  if open then reaper.defer(loop) end
end

reaper.defer(loop)
