-- Flight instrumentation and menus share the engine's Yoga/NanoVG UI tree.
local UI = require("urhox-libs/UI")
local Flight = require("Game.Flight")
local HUD = {}
HUD.__index = HUD
local WHITE, MUTED, CYAN = {235, 243, 244, 255}, {207, 222, 226, 255}, {118, 221, 211, 255}
local AMBER, RED = {239, 187, 105, 255}, {247, 118, 100, 255}
local function label(text, size, color, extra)
    local props = {text = text, fontSize = size, fontColor = color or WHITE, pointerEvents = "none",
        textShadow = {offsetX = 0, offsetY = 0, blur = 4, color = {2, 9, 14, 150}}}
    for k, v in pairs(extra or {}) do props[k] = v end
    return UI.Label(props)
end
local Instruments = UI.Widget:Extend("FlightInstruments")
function Instruments:Init(props) UI.Widget.Init(self, props) end

--- Draw live instrument scales in the UI pass; leave the central flight path unobstructed.
function Instruments:Render(vg)
    local flight, camera = self.props.flight, self.props.camera
    if flight.mode ~= "flight" then return end
    local l = self:GetAbsoluteLayout()
    nvgSave(vg)
    local function line(x1, y1, x2, y2, alpha)
        nvgBeginPath(vg); nvgMoveTo(vg, x1, y1); nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBA(223, 238, 241, alpha or 180)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    end
    if not self.props.cockpit then
        -- Soft edge falloff keeps instruments legible over sun glare without boxed cards.
        local cy = l.y + l.h * 0.44 + 43
        for _, x in ipairs({l.x - 40, l.x + l.w + 40}) do
            local shade = nvgRadialGradient(vg, x, cy, 40, 310,
                nvgRGBA(5, 14, 20, 215), nvgRGBA(5, 14, 20, 0))
            nvgBeginPath(vg); nvgRect(vg, l.x, l.y, l.w, l.h)
            nvgFillPaint(vg, shade); nvgFill(vg)
        end
        local heading = flight.rotation.yawAngle % 360
        local cx, top = l.x + l.w / 2, l.y + 66
        nvgFontFace(vg, UI.Theme.FontFace("mono")); nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER | NVG_ALIGN_TOP)
        for value = math.floor(heading / 5) * 5 - 30, math.floor(heading / 5) * 5 + 35, 5 do
            local x = cx + (value - heading) * 4
            if math.abs(x - cx) < 124 then
                local alpha = math.floor(190 * (1 - math.abs(x - cx) / 160))
                line(x, top, x, top + (value % 10 == 0 and 8 or 4), alpha)
                if value % 10 == 0 then
                    nvgFillColor(vg, nvgRGBA(193, 224, 225, alpha))
                    nvgText(vg, x, top + 12, string.format("%03d", value % 360), nil)
                end
            end
        end
        line(cx, top - 6, cx, top + 5, 240)
        for _, tape in ipairs({{l.x + 176, flight.speed * 3.6, -1},
            {l.x + l.w - 176, flight.position.y, 1}}) do
            local x, value, side = table.unpack(tape)
            for mark = math.floor(value / 10) * 10 - 40, math.floor(value / 10) * 10 + 40, 10 do
                local y = cy - (mark - value) * 1.8
                if mark >= 0 and math.abs(y - cy) < 64 then
                    line(x, y, x + side * (mark % 20 == 0 and 12 or 6), y,
                        math.floor(230 * (1 - math.abs(y - cy) / 90)))
                end
            end
            nvgBeginPath(vg)
            nvgMoveTo(vg, x - side * 5, cy); nvgLineTo(vg, x - side * 12, cy - 4)
            nvgLineTo(vg, x - side * 12, cy + 4); nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(118, 221, 211, 230)); nvgFill(vg)
        end
    end
    local p = camera:WorldToScreenPoint(flight.position + flight.velocity * 4)
    if p.x >= 0.08 and p.x <= 0.92 and p.y >= 0.12 and p.y <= 0.78 then
        local x, y = l.x + p.x * l.w, l.y + p.y * l.h
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, 6)
        nvgMoveTo(vg, x - 18, y); nvgLineTo(vg, x - 6, y)
        nvgMoveTo(vg, x + 6, y); nvgLineTo(vg, x + 18, y)
        nvgMoveTo(vg, x, y - 13); nvgLineTo(vg, x, y - 6)
        nvgStrokeColor(vg, nvgRGBA(185, 235, 239, 210))
        nvgStrokeWidth(vg, 1.2); nvgStroke(vg)
    end
    nvgRestore(vg)
end

--- Build an aviation HUD with flat command keys, edge instruments and a clear center.
function HUD.Create(flight, camera, action)
    local self = setmetatable({flight = flight, timer = 0.0}, HUD)
    local theme = UI.Theme.ExtendTheme(UI.Theme.GetRegisteredTheme("default-dark"), {
        colors = {primary = CYAN, primaryHover = {155, 238, 229, 255}, primaryPressed = {88, 181, 174, 255},
            secondary = {8, 18, 25, 0}, secondaryHover = {113, 194, 201, 35},
            secondaryPressed = {113, 194, 201, 65}, text = WHITE},
        componentDefaults = {borderRadius = 0},
        components = {Button = {height = 34, borderRadius = 2, borderWidth = 0,
            fontSize = 10, fontWeight = "normal", padding = {0, 10}, pressedPadding = {0, 10},
            glowShadow = false, boxShadow = false,
            variantTextColor = {primary = {8, 24, 29, 255}, secondary = WHITE}}},
    })
    UI.Init({theme = theme, scale = UI.Scale.DEFAULT, fonts = {
        {family = "sans", weights = {normal = "Fonts/NotoSansSC-Regular.ttf", bold = "Fonts/NotoSansSC-Bold.ttf"}},
        {family = "mono", weights = {normal = "Fonts/Anonymous Pro.ttf"}},
    }})
    self.title = label("BLACK EMPEROR", 32, WHITE, {fontWeight = "bold", letterSpacing = 1})
    self.subtitle = label("黑帝 · R06  /  01 号试飞机", 13, WHITE)
    self.hint = label("六道航门。一公里海面。你的第一次试飞。", 11, MUTED)
    self.hero = UI.Panel {position = "absolute", left = 36, top = 128, gap = 12, pointerEvents = "none",
        children = {UI.Panel {width = 32, height = 2, backgroundColor = CYAN},
            label("EXPERIMENTAL  /  FLIGHT TRIAL", 9, CYAN, {letterSpacing = 2}),
            self.title, self.subtitle, self.hint}}
    self.speed = label("169", 36, WHITE, {fontWeight = "bold", lineHeight = 1.05})
    self.altitude = label("075", 36, WHITE, {fontWeight = "bold", lineHeight = 1.05})
    self.power = label("54%", 17, WHITE, {fontWeight = "bold"})
    local function metric(name, value, unit, side)
        return UI.Panel {position = "absolute", [side] = 0, width = 130, gap = 4,
            alignItems = side == "right" and "flex-end" or "flex-start", children = {
                label(name, 9, MUTED, {letterSpacing = 1.5}), value,
                label(unit, 9, MUTED, {fontFamily = "mono", letterSpacing = 1})}}
    end
    self.telemetry = UI.Panel {position = "absolute", top = "44%", left = 36, right = 36, height = 112,
        pointerEvents = "none", children = {
            metric("AIR SPEED", self.speed, "KM/H", "left"), metric("RADAR ALT", self.altitude, "M / AGL", "right")}}
    self.powerFill = UI.Panel {height = 2, width = "54%", backgroundColor = CYAN}
    self.gear = label("GEAR UP", 9, MUTED, {fontFamily = "mono"})
    self.engine = UI.Panel {position = "absolute", bottom = 76, left = 36, width = 178, gap = 6,
        pointerEvents = "none", children = {
            UI.Panel {flexDirection = "row", alignItems = "baseline", justifyContent = "space-between",
                children = {label("THROTTLE", 9, MUTED, {letterSpacing = 1.2}), self.power}},
            UI.Panel {height = 2, backgroundColor = {166, 200, 207, 55}, children = {self.powerFill}}, self.gear}}
    self.count = label("00 / 06", 20, WHITE, {fontFamily = "mono"})
    self.clock = label("T+ 00:00.0", 10, MUTED, {fontFamily = "mono"})
    self.wind = label("CROSSWIND 01", 8.5, MUTED, {fontFamily = "mono"})
    self.nextGate = label("NEXT 01", 10, CYAN, {fontFamily = "mono"})
    self.bars = {}
    for i = 1, 6 do self.bars[i] = UI.Panel {width = 27, height = 2, backgroundColor = {151, 176, 183, 65}} end
    self.mission = UI.Panel {position = "absolute", top = 30, right = 36, width = 192,
        gap = 7, alignItems = "flex-end", pointerEvents = "none", children = {
            label("MARITIME  /  FLIGHT TRIAL", 8.5, MUTED, {letterSpacing = 1}),
            UI.Panel {width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "baseline",
                children = {self.clock, self.count}},
            UI.Panel {flexDirection = "row", gap = 6, children = self.bars}, self.nextGate, self.wind}}
    self.heading = label("000", 19, WHITE, {fontFamily = "mono"})
    self.navigation = UI.Panel {position = "absolute", top = 20, left = 0, right = 0, alignItems = "center",
        pointerEvents = "none", children = {label("HDG", 8, MUTED, {letterSpacing = 2}), self.heading}}
    self.status = label("系统就绪 · 起落架收起", 9, MUTED)
    self.toast = label("", 13, CYAN, {letterSpacing = 1})
    self.noticeRule = UI.Panel {width = 24, height = 1, backgroundColor = CYAN}
    self.notice = UI.Panel {position = "absolute", top = 126, left = 0, right = 0,
        alignItems = "center", visible = false, pointerEvents = "none", children = {
            UI.Panel {padding = {8, 16}, gap = 6, alignItems = "center", backgroundColor = {5, 14, 20, 180},
                children = {self.noticeRule, self.toast}}}}
    local function button(text, key, primary)
        return UI.Button {text = text, height = primary and 40 or 34,
            variant = primary and "primary" or "secondary", onClick = function() action(key) end}
    end
    self.start = button("开始试飞  Enter", "start", true)
    self.camera = button("C  /  绕机巡览", "camera")
    self.controls = UI.Panel {position = "absolute", bottom = 16, right = 28, flexDirection = "row", gap = 8,
        alignItems = "center", children = {self.start, self.camera, button("G  /  起落架", "gear"),
            button("P  /  纯净画面", "photo"), button("F1  /  操作", "help")}}
    local function binding(keys, description)
        return UI.Panel {flexDirection = "row", gap = 12, alignItems = "baseline", children = {
            label(keys, 12, MUTED, {width = 148}), label(description, 12)}}
    end
    self.manual = UI.Panel {position = "absolute", top = 100, left = 36, width = 404, padding = 24, gap = 12,
        backgroundColor = {8, 17, 23, 246}, borderTopWidth = 2, borderTopColor = CYAN, visible = false, children = {
            label("FLIGHT MANUAL / 操作指南", 15, CYAN),
            binding("W / S 或 ↑ / ↓", "抬头 / 低头"),
            binding("A / D 或 ← / →", "左右横滚"),
            binding("Q / E", "左右偏航"),
            binding("Shift / Ctrl", "增减油门"),
            binding("C", "追尾 / 座舱 / 侧视"),
            label("G 起落架  ·  R 换侧风重飞", 12),
            label("座舱：按住右键环顾，松开回正", 11, CYAN),
            label("巡览：鼠标拖动 / 滚轮缩放 / V 舱盖", 11, MUTED),
            label("手柄：左摇杆俯仰横滚，右摇杆偏航\n扳机油门；A 开始，B 重飞，X 起落架，Y 镜头", 12, MUTED, {textAlign = "left"}),
            button("收起指南  Esc", "help", true)}}
    self.lookHint = UI.Panel {position = "absolute", top = 24, left = 36, visible = false, pointerEvents = "none",
        padding = {6, 10}, backgroundColor = {5, 14, 20, 170},
        children = {label("RMB  /  环顾座舱 · 松开回正", 9, MUTED)}}
    self.instruments = Instruments {width = "100%", height = "100%", position = "absolute",
        pointerEvents = "none", flight = flight, camera = camera}
    local content = UI.Panel {width = "100%", height = "100%", pointerEvents = "box-none", children = {
        self.instruments, self.navigation,
        UI.Panel {id = "brand", position = "absolute", top = 28, left = 36, gap = 7, pointerEvents = "none", children = {
            label("TRIDENT  /  R06", 12, WHITE, {letterSpacing = 3}),
            label("试飞计划    /    海上靶场", 9, MUTED, {letterSpacing = 1})}},
        self.hero, self.telemetry, self.engine, self.mission, self.notice, self.lookHint,
        UI.Panel {position = "absolute", left = 36, bottom = 26, pointerEvents = "none", children = {self.status}},
        self.controls, self.manual,
    }}
    self.root = UI.Panel {width = "100%", height = "100%", pointerEvents = "box-none", children = {
        UI.Panel {id = "topShade", position = "absolute", top = 0, left = 0, right = 0, height = 240, pointerEvents = "none",
            backgroundGradient = {direction = "to-bottom", from = {5, 14, 20, 210}, to = {5, 14, 20, 0}}},
        UI.Panel {id = "bottomShade", position = "absolute", bottom = 0, left = 0, right = 0, height = 210, pointerEvents = "none",
            backgroundGradient = {direction = "to-top", from = {5, 14, 20, 210}, to = {5, 14, 20, 0}}},
        UI.SafeAreaView {width = "100%", height = "100%", pointerEvents = "box-none", children = {content}},
    }}
    UI.SetRoot(self.root)
    return self
end

--- Update telemetry at 10 Hz; keep the world visible while displaying trial outcomes.
function HUD:Update(dt, state)
    self.root:SetVisible(not state.photo)
    self.timer = self.timer + dt
    if self.timer < 0.1 then return end
    self.timer = self.timer % 0.1
    local f, flying = self.flight, self.flight.mode == "flight"
    local inCockpit = flying and state.view == 2
    self.mission:SetVisible(not inCockpit and not state.help)
    self.lookHint:SetVisible(inCockpit and not state.help)
    for _, id in ipairs({"brand", "topShade", "bottomShade"}) do self.root:FindById(id):SetVisible(not inCockpit) end
    self.navigation:SetVisible(flying and not inCockpit and not state.help)
    self.instruments:SetVisible(flying and not state.help)
    self.instruments.props.cockpit = inCockpit
    self.hero:SetVisible(not flying and not state.help)
    self.status:SetVisible(not flying and not state.help)
    self.telemetry:SetVisible(not state.help and not inCockpit)
    self.telemetry:SetStyle({top = flying and "44%" or "54%"})
    self.engine:SetVisible(not state.help and not inCockpit)
    self.controls:SetStyle({bottom = inCockpit and 6 or 16})
    self.start:SetVisible(not flying and not state.help)
    self.title:SetText(f.mode == "ready" and "BLACK EMPEROR" or (f.mode == "finish" and "航线完成" or "试飞中止"))
    self.subtitle:SetText(f.mode == "ready" and "黑帝 · R06  /  01 号试飞机" or string.format("%d / 6 道航门通过  ·  %.2f 秒", f.hits, f.time))
    self.hint:SetText(f.mode == "ready" and "六道航门。一公里海面。你的第一次试飞。" or "按 Enter 重新试飞；R 切换侧风条件。")
    self.start:SetText(f.mode == "ready" and "开始试飞  Enter" or "重新试飞  Enter")
    self.camera:SetText("C  /  " .. (flying and ({"追尾视角", "座舱视角", "侧面视角"})[state.view] or "绕机巡览"))
    self.speed:SetText(string.format("%03d", math.floor(f.speed * 3.6 + 0.5)))
    self.altitude:SetText(string.format("%03d", math.max(0, math.floor(f.position.y + 0.5))))
    self.power:SetText(string.format("%d%%", math.floor(f.throttle * 100 + 0.5)))
    self.powerFill:SetStyle({width = string.format("%d%%", math.floor(f.throttle * 100 + 0.5))})
    self.gear:SetText(state.gear and "GEAR DOWN" or "GEAR UP")
    self.gear:SetStyle({fontColor = state.gear and AMBER or MUTED})
    self.heading:SetText(string.format("%03d", math.floor(f.rotation.yawAngle % 360 + 0.5) % 360))
    self.count:SetText(string.format("%02d / 06", f.hits))
    self.clock:SetText(string.format("T+ %02d:%04.1f", math.floor(f.time / 60), f.time % 60))
    self.wind:SetText(({"CROSSWIND 01 / 2.6 m/s", "CROSSWIND 02 / 4.7 m/s", "CROSSWIND 03 / 6.6 m/s"})[f.wind])
    local gate = Flight.GATES[f.index]
    local distance = gate and (Vector3(gate[1], gate[2], gate[3]) - f.position):Length() or 0
    self.nextGate:SetText(gate and string.format("NEXT %02d   /   %03d M", f.index, math.floor(distance + 0.5)) or "TRIAL COMPLETE")
    self.status:SetText((state.gear and "起落架放下" or "起落架收起") .. " · " .. (flying and "W/S 俯仰 · A/D 横滚" or "拖动巡览 · 滚轮缩放"))
    local low = flying and f.position.y < 15
    local notifying = flying and (low or f.time < f.pulseEnd)
    local noticeColor = low and AMBER or (f.pulse == "错过航门" and RED or CYAN)
    self.notice:SetVisible(notifying and not state.help)
    self.notice:SetOpacity(low and 1 or math.min(1, math.max(0, (f.pulseEnd - f.time) / 0.35)))
    self.toast:SetText(low and "低空警告 / PULL UP" or f.pulse)
    self.toast:SetStyle({fontColor = noticeColor})
    self.noticeRule:SetStyle({backgroundColor = noticeColor})
    self.altitude:SetStyle({fontColor = low and AMBER or WHITE})
    for i, bar in ipairs(self.bars) do
        local color = f.outcomes[i] == true and CYAN or
            (f.outcomes[i] == false and RED or (i == f.index and WHITE or {151, 176, 183, 65}))
        bar:SetStyle({backgroundColor = color})
    end
end

return HUD
