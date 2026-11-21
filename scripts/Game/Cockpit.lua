-- A pilot-sized cockpit tub, panoramic avionics and physical HOTAS, independent of head orientation.
local PropBuilder = require("urhox-libs/Geometry/PropBuilder")
local TextureBaker = require("urhox-libs/Rendering/TextureBaker")
local DecalAtlas = require("urhox-libs/Rendering/DecalAtlas")
local Flight = require("Game.Flight")
local Cockpit = {}
Cockpit.__index = Cockpit

local function solid(color, roughness, metal, emission)
    local m = Material:new()
    m:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    m:SetShaderParameter("MatDiffColor", Variant(color))
    m:SetShaderParameter("Roughness", Variant(roughness))
    m:SetShaderParameter("Metallic", Variant(metal))
    if emission then m:SetShaderParameter("MatEmissiveColor", Variant(emission)) end
    return m
end

--- Build a complete enclosure around the pilot, rather than mounting three boxes on the camera.
function Cockpit.Create(scene, flight)
    local self = setmetatable({flight = flight, dirty = true, timer = 0.0}, Cockpit)
    self.node = scene:CreateChild("Cockpit")
    local b = PropBuilder.new()
    local materials = {
        shell = TextureBaker.CreateMaterial("anodized_black", {macro = false, normalScale = 0.2, uvScale = 24}),
        carbon = TextureBaker.CreateMaterial("carbon", {macro = false, normalScale = 0.15, uvScale = 60,
            color = Color(0.28, 0.32, 0.36), roughnessScale = 1.45}),
        rubber = TextureBaker.CreateMaterial("rubber", {macro = false, normalScale = 0.2, uvScale = 100}),
        trim = solid(Color(0.29, 0.33, 0.35), 0.34, 0.8),
        key = solid(Color(0.20, 0.24, 0.25), 0.6, 0.15),
        amber = solid(Color(0.83, 0.53, 0.09), 0.55, 0.0),
        light = solid(Color(0.05, 0.3, 0.24), 0.45, 0.0, Vector3(0.03, 0.6, 0.38)),
    }
    local function box(mat, w, h, d, x, y, z, bevel)
        b:Add(mat, ChamferBoxGeometry(w, h, d, bevel or math.min(0.008, w / 4, h / 4, d / 4)):Translate(x, y, z))
    end
    local function screw(x, y, z)
        b:Add("trim", CylinderGeometry(0.008, 0.008, 0.004, 12)
            :ApplyQuaternion(Quaternion(90, Vector3.RIGHT)):Translate(x, y, z))
        box("rubber", 0.009, 0.0015, 0.002, x, y, z - 0.003, 0.0004)
    end
    local atlas = DecalAtlas.new({size = 1024})
    for _, name in ipairs({"NAV / COM", "FLIGHT CONTROL", "CANOPY LOCK", "EJECTION", "R06  /  FLIGHT SYSTEMS", "AUX POWER"}) do
        atlas:Add(name, 480, 64, function(vg, w, h)
            DecalAtlas.Text(vg, name, w / 2, h / 2, {size = 34, spacing = 2, maxWidth = w - 16,
                color = name == "EJECTION" and nvgRGB(232, 177, 67) or nvgRGB(165, 184, 185)})
        end)
    end
    atlas:Bake()
    materials.label = atlas:CreateSharedMaterial()
    local function plate(name, height, x, y, z)
        b:Add("label", atlas:MapUV(atlas:Plane(name, height), name):Translate(x, y, z), {castShadows = false})
    end
    -- Continuous floor, side walls and a front bulkhead close the tub below every instrument.
    box("shell", 1.65, 0.07, 2.6, 0, -1.08, 0.50, 0.025)
    box("shell", 1.73, 0.8, 0.08, 0, -0.65, -0.65, 0.025)
    box("carbon", 1.73, 0.9, 0.13, 0, -0.64, 1.45, 0.035)
    for _, side in ipairs({-1, 1}) do
        box("shell", 0.12, 0.9, 2.25, side * 0.87, -0.63, 0.45, 0.035)
        b:Push(Vector3(side * 0.23, -0.90, 1.05), Quaternion(55, 0, 0))
        box("trim", 0.18, 0.28, 0.035, 0, 0, 0)
        for i = -3, 3 do box("rubber", 0.14, 0.012, 0.008, 0, i * 0.034, -0.022, 0.003) end
        b:Pop()
    end
    local consoleMounts = {}
    local function sillTop(z)
        return -0.27 + (z + 0.3) * 0.05 / 1.38
    end
    -- The front windscreen has no center post; the canopy bow is behind the pilot's normal sightline.
    for _, side in ipairs({-1, 1}) do
        -- Follow the sill before turning upwards; sparse spline points previously dipped into its top face.
        local rail = {Vector3(side * 0.53, sillTop(-0.65) + 0.034, -0.65),
            Vector3(side * 0.68, sillTop(0) + 0.034, 0),
            Vector3(side * 0.76, sillTop(0.8) + 0.034, 0.8),
            Vector3(side * 0.75, sillTop(1.08) + 0.034, 1.08),
            Vector3(side * 0.73, -0.10, 1.24), Vector3(side * 0.70, 0.10, 1.34),
            Vector3(side * 0.67, 0.35, 1.42), Vector3(side * 0.43, 0.9, 1.56)}
        b:Add("shell", TubeGeometry(rail, 72, 0.026, 12):ScaleUVToMeters())
        b:Add("rubber", TubeGeometry(rail, 72, 0.011, 8):Translate(-side * 0.024, 0.018, -0.015):ScaleUVToMeters())
        -- Keep the liner outside the console envelope instead of tapering through the instrument faces.
        local liner = {}
        for _, z in ipairs({-0.6, 1.35}) do
            for _, edge in ipairs({{0.785, -1.04}, {0.815, -0.22}, {0.86, -0.22}, {0.86, -1.04}}) do
                liner[#liner + 1] = Vector3(side * edge[1], edge[2], z)
            end
        end
        b:Add("carbon", ConvexGeometry(liner))
        -- One tapered sill carries two flush dark latch covers; there are no exposed silver brackets.
        local sill = {}
        for _, endPoint in ipairs({{0.62, sillTop(-0.3), -0.3}, {0.70, sillTop(1.08), 1.08}}) do
            for _, x in ipairs({endPoint[1], 0.88}) do
                for _, depth in ipairs({0, -0.045}) do
                    sill[#sill + 1] = Vector3(side * x, endPoint[2] + depth, endPoint[3])
                end
            end
        end
        b:Add("shell", ConvexGeometry(sill))
        for _, z in ipairs({0.30, 0.76}) do
            b:Push(Vector3(side * (0.62 + (z + 0.3) * 0.08 / 1.38 - 0.002),
                sillTop(z) - 0.022, z), Quaternion(0, side * 93.32, 0))
            box("rubber", 0.13, 0.028, 0.004, 0, 0, 0, 0.001)
            box("shell", 0.118, 0.021, 0.002, 0, 0, -0.003, 0.0005)
            box("rubber", 0.03, 0.003, 0.001, 0, 0, -0.0045, 0.0002)
            b:Pop()
        end
        -- Keep the consoles beside the seat, clear of the panoramic display's sightlines.
        local consolePosition = Vector3(side * 0.61, -0.64, 0.35)
        local consoleRotation = Quaternion(58, 0, 0)
        consoleMounts[side] = consolePosition + consoleRotation * Vector3(-side * 0.045, 0.24, -0.105)
        local pedestal = {}
        for _, x in ipairs({-0.14, 0.14}) do
            for _, y in ipairs({-0.40, 0.40}) do
                pedestal[#pedestal + 1] = consolePosition + consoleRotation * Vector3(x, y, 0.045)
            end
        end
        for _, x in ipairs({0.45, 0.77}) do
            for _, z in ipairs({-0.10, 0.72}) do pedestal[#pedestal + 1] = Vector3(side * x, -1.04, z) end
        end
        b:Add("shell", ConvexGeometry(pedestal))
        b:Push(consolePosition, consoleRotation)
        box("shell", 0.31, 0.84, 0.095, 0, 0, 0, 0.025)
        box("carbon", 0.285, 0.805, 0.015, 0, 0, -0.054)
        for section = 0, 2 do
            local y = 0.27 - section * 0.25
            box("key", 0.252, 0.224, 0.012, 0, y, -0.065)
            for _, x in ipairs({-0.112, 0.112}) do
                screw(x, y - 0.095, -0.074); screw(x, y + 0.095, -0.074)
            end
            -- Reserve the upper island for HOTAS, without switches hidden beneath the grip.
            if section > 0 then
                for row = 0, 1 do
                    for col = 0, 3 do
                        box("rubber", 0.039, 0.036, 0.012, -0.077 + col * 0.052, y + 0.025 - row * 0.064, -0.081)
                        box((col + row + section) % 4 == 0 and "light" or "trim", 0.021, 0.003, 0.002,
                            -0.077 + col * 0.052, y + 0.025 - row * 0.064, -0.088)
                    end
                end
            end
        end
        box("rubber", 0.15, 0.13, 0.024, -side * 0.045, 0.255, -0.085, 0.006)
        plate(side < 0 and "NAV / COM" or "FLIGHT CONTROL", 0.027, 0, 0.34, -0.075)
        plate("AUX POWER", 0.023, 0, -0.16, -0.075)
        b:Pop()
        b:Push(Vector3(side * 0.724, -0.255, 0.02), Quaternion(87.925, 0, 0))
        plate("CANOPY LOCK", 0.014, 0, 0, 0)
        b:Pop()
    end
    b:Add("shell", TubeGeometry({Vector3(-0.64, -0.22, -0.32), Vector3(-0.60, 0.5, -0.38),
        Vector3(0, 0.86, -0.40), Vector3(0.60, 0.5, -0.38), Vector3(0.64, -0.22, -0.32)}, 80, 0.045, 12):ScaleUVToMeters())
    box("rubber", 0.53, 0.11, 0.65, 0, -0.88, 0.07, 0.04)
    box("carbon", 0.58, 0.62, 0.12, 0, -0.57, -0.43, 0.04)
    box("rubber", 0.25, 0.20, 0.11, 0, -0.13, -0.45, 0.045)
    b:Add("amber", TubeGeometry({Vector3(-0.09, -0.80, 0.24), Vector3(-0.075, -0.73, 0.26),
        Vector3(0.075, -0.73, 0.26), Vector3(0.09, -0.80, 0.24)}, 24, 0.012, 8))
    b:Push(Vector3(0, -0.82, 0.37), Quaternion(90, 0, 0))
    plate("EJECTION", 0.023, 0, 0, 0)
    b:Pop()
    -- One contiguous, tilted wide-area display, with a thin edge instead of three deep bezels.
    b:Push(Vector3(0, -0.45, 1.06), Quaternion(18, 0, 0))
    box("shell", 1.22, 0.52, 0.10, 0, 0, 0, 0.025)
    box("trim", 1.175, 0.475, 0.012, 0, 0, -0.055)
    box("rubber", 1.16, 0.46, 0.016, 0, 0, -0.063)
    self.texture = Texture2D:new()
    self.texture:SetNumLevels(1)
    assert(self.texture:SetSize(2304, 900, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET))
    self.texture:SetFilterMode(FILTER_BILINEAR)
    self.displayMaterial = Material:new()
    assert(self.displayMaterial:SetSurfaceShader("Shaders/Avionics.shader"))
    self.displayMaterial:SetSurfaceTexture("display", self.texture)
    materials.display = self.displayMaterial
    b:Add("display", PlaneGeometry(1.125, 0.439):Translate(0, 0, -0.074), {castShadows = false})
    for i = -5, 5 do
        box("key", 0.062, 0.014, 0.012, i * 0.102, 0.247, -0.060)
    end
    for _, x in ipairs({-0.59, 0.59}) do
        screw(x, -0.235, -0.057); screw(x, 0.235, -0.057)
    end
    plate("R06  /  FLIGHT SYSTEMS", 0.022, 0, -0.249, -0.060)
    b:Pop()
    box("carbon", 1.26, 0.055, 0.32, 0, -0.16, 1.26, 0.018)
    box("rubber", 1.28, 0.045, 0.08, 0, -0.167, 1.10, 0.017)
    for side = -1, 1, 2 do
        b:Push(Vector3(side * 0.58, -0.17, 1.09), Quaternion(15, 0, 0))
        box("amber", 0.045, 0.019, 0.008, 0, 0, 0)
        b:Pop()
    end
    PropBuilder.Attach(self.node, b:Build(), materials)
    -- Separate rigid assemblies animate with the player's inputs, not with the head camera.
    self.stick = self.node:CreateChild("SideStick")
    self.stick.position = consoleMounts[1]
    local stick = PropBuilder.new()
    stick:Add("rubber", CylinderGeometry(0.042, 0.055, 0.055, 24)
        :ApplyQuaternion(Quaternion(-32, 0, 0)):Translate(0, 0.025, 0):ScaleUVToMeters())
    stick:Add("trim", CylinderGeometry(0.016, 0.020, 0.09, 20):Translate(0, 0.075, 0):ScaleUVToMeters())
    stick:Add("rubber", RoundedBoxGeometry(0.072, 0.115, 0.09, 4, 0.018):Translate(0, 0.16, 0):ScaleUVToMeters())
    stick:Add("key", CylinderGeometry(0.014, 0.017, 0.012, 16):Translate(-0.02, 0.224, -0.015))
    stick:Add("amber", SphereGeometry(0.012, 12, 8):Translate(0.024, 0.21, -0.04))
    PropBuilder.Attach(self.stick, stick:Build(), materials)
    self.throttle = self.node:CreateChild("Throttle")
    self.throttle.position = consoleMounts[-1]
    local throttle = PropBuilder.new()
    throttle:Add("shell", ChamferBoxGeometry(0.09, 0.14, 0.04, 0.01):Translate(0, 0.015, 0))
    throttle:Add("rubber", RoundedBoxGeometry(0.16, 0.065, 0.11, 4, 0.017):Translate(0, 0.095, 0):ScaleUVToMeters())
    throttle:Add("key", CylinderGeometry(0.013, 0.013, 0.01, 16):Translate(0.05, 0.135, 0))
    PropBuilder.Attach(self.throttle, throttle:Build(), materials)
    self.context = assert(nvgCreate(1))
    assert(nvgCreateFont(self.context, "mono", "Fonts/Anonymous Pro.ttf") >= 0)
    nvgSetRenderTarget(self.context, self.texture)
    self.receiverNode = Node()
    self.receiver = self.receiverNode:CreateScriptObject("LuaScriptObject")
    self.receiver:SubscribeToEvent(self.context, "NanoVGRender", function() self:Render() end)
    self.node:SetDeepEnabled(false)
    return self
end

--- Place the cockpit in aircraft space and animate controls; head motion does not move the cabin.
function Cockpit:Update(dt, visible, position, rotation, controls)
    self.node.position, self.node.rotation = position, rotation
    self.node:SetDeepEnabled(visible)
    self.stick.rotation = Quaternion(-controls.pitch * 13, 0, -controls.roll * 13)
    self.throttle.rotation = Quaternion((self.flight.throttle - 0.5) * 35, 0, 0)
    self.displayMaterial:SetSurfaceTexture("display", self.texture)
    self.timer = self.timer + dt
    if visible and self.timer >= 1 / 30 then self.timer, self.dirty = 0, true end
end

--- Render real flight and course data into the panoramic screen, in its texture render event.
function Cockpit:Render()
    if not self.dirty then return end
    self.dirty = false
    local vg, f = self.context, self.flight
    local cyan, white, muted = nvgRGB(103, 213, 208), nvgRGB(220, 232, 225), nvgRGB(98, 126, 135)
    local amber = nvgRGB(234, 179, 75)
    local function text(s, x, y, size, color)
        nvgFontFace(vg, "mono"); nvgFontSize(vg, size)
        nvgTextAlign(vg, NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, color or white); nvgText(vg, x, y, s, nil)
    end
    local function line(x1, y1, x2, y2, color, width)
        nvgBeginPath(vg); nvgMoveTo(vg, x1, y1); nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, color or muted); nvgStrokeWidth(vg, width or 1.5); nvgStroke(vg)
    end
    local function rect(x, y, w, h, color)
        nvgBeginPath(vg); nvgRect(vg, x, y, w, h); nvgFillColor(vg, color); nvgFill(vg)
    end
    nvgBeginFrame(vg, 1536, 600, 1.5)
    rect(0, 0, 1536, 600, nvgRGB(4, 10, 15))
    rect(0, 0, 1536, 55, nvgRGB(17, 31, 38))
    text("TRIDENT  /  R06", 24, 28, 28, cyan)
    text("FLIGHT TEST", 420, 28, 25)
    text(string.format("COURSE %02d / 06", f.hits), 763, 28, 25)
    text(string.format("T+ %05.1f", f.time), 1260, 28, 27)
    line(400, 72, 400, 535); line(1138, 72, 1138, 535)
    text("PRIMARY FLIGHT", 24, 88, 22, muted)
    text("AIR SPEED", 24, 128, 19, muted); text("ALTITUDE", 234, 128, 19, muted)
    text(string.format("%03d", math.floor(f.speed * 3.6 + 0.5)), 24, 175, 59)
    text(string.format("%03d", math.max(0, math.floor(f.position.y + 0.5))), 234, 175, 59)
    text("KM/H", 130, 189, 18, muted); text("M", 344, 189, 18, muted)
    nvgSave(vg); nvgScissor(vg, 50, 229, 300, 218)
    nvgTranslate(vg, 200, 336); nvgRotate(vg, math.rad(f.rotation.rollAngle))
    nvgTranslate(vg, 0, -f.rotation.pitchAngle * 2.7)
    rect(-600, -600, 1200, 600, nvgRGB(20, 53, 68)); rect(-600, 0, 1200, 600, nvgRGB(49, 44, 30))
    line(-600, 0, 600, 0, white, 2)
    for a = -80, 80, 10 do
        if a ~= 0 then
            local w = a % 20 == 0 and 46 or 28
            line(-w, -a * 2.7, w, -a * 2.7, white)
        end
    end
    nvgRestore(vg)
    line(150, 336, 185, 336, amber, 4); line(215, 336, 250, 336, amber, 4)
    line(185, 336, 200, 345, amber, 4); line(200, 345, 215, 336, amber, 4)
    text(string.format("AOA %+04.1f", math.deg(f.aoa)), 30, 485, 25)
    text(string.format("V/S %+04.1f", f.velocity.y), 220, 485, 25)
    -- The navigation pane dominates the display, matching wide-area cockpit layouts.
    text("MARITIME RANGE / ROUTE", 427, 88, 23, cyan)
    text(string.format("HDG %03d", math.floor(f.rotation.yawAngle % 360 + 0.5) % 360), 970, 88, 23)
    local heading = Quaternion(0, f.rotation.yawAngle, 0):Inverse()
    nvgSave(vg); nvgScissor(vg, 420, 112, 700, 415)
    for i = -5, 5 do
        line(775 + i * 64, 112, 775 + i * 64, 527, nvgRGB(20, 39, 48))
        line(420, 410 + i * 64, 1120, 410 + i * 64, nvgRGB(20, 39, 48))
    end
    for _, r in ipairs({120, 240, 360}) do
        nvgBeginPath(vg); nvgCircle(vg, 775, 410, r)
        nvgStrokeColor(vg, nvgRGB(45, 73, 82)); nvgStrokeWidth(vg, 1); nvgStroke(vg)
    end
    local last
    for i, gate in ipairs(Flight.GATES) do
        local d = heading * (Vector3(gate[1], gate[2], gate[3]) - f.position)
        local x, y = 775 + d.x * 0.6, 410 - d.z * 0.6
        if last then line(last.x, last.y, x, y, muted, 2) end
        last = {x = x, y = y}
        local color = i == f.index and cyan or (f.outcomes[i] == false and amber or muted)
        nvgBeginPath(vg); nvgCircle(vg, x, y, i == f.index and 11 or 6)
        nvgStrokeColor(vg, color); nvgStrokeWidth(vg, 2); nvgStroke(vg)
        text(string.format("G%02d", i), x + 20, y, 24, color)
    end
    line(759, 427, 775, 395, white, 3); line(775, 395, 791, 427, white, 3); line(759, 427, 791, 427, white, 3)
    nvgRestore(vg)
    text("500 M", 430, 513, 20, muted)
    text("AIRFRAME / PROPULSION", 1164, 88, 22, muted)
    local shape = {{1335, 125}, {1360, 194}, {1480, 260}, {1370, 243}, {1350, 271},
        {1320, 271}, {1300, 243}, {1190, 260}, {1310, 194}, {1335, 125}}
    for i = 2, #shape do line(shape[i - 1][1], shape[i - 1][2], shape[i][1], shape[i][2], cyan, 2) end
    text("THROTTLE", 1164, 316, 23, muted)
    text(string.format("%03d%%", math.floor(f.throttle * 100 + 0.5)), 1360, 318, 44, cyan)
    rect(1168, 364, 330, 16, nvgRGB(24, 43, 50)); rect(1168, 364, 330 * f.spool, 16, cyan)
    text(string.format("SPOOL %03d%%", math.floor(f.spool * 100 + 0.5)), 1164, 410, 24)
    text(self.gear and "GEAR / DOWN" or "GEAR / UP", 1164, 462, 26, self.gear and amber or white)
    text(f.position.y < 15 and "PULL UP" or "FLIGHT CONTROL / MANUAL", 1164, 510, 21,
        f.position.y < 15 and amber or muted)
    rect(0, 548, 1536, 52, nvgRGB(14, 26, 32))
    text("PFD", 35, 574, 23, cyan); text("NAV", 180, 574, 23, cyan); text("SYS", 330, 574, 23, muted)
    text(string.format("CROSSWIND %02d", f.wind), 560, 574, 23)
    text(string.format("NEXT GATE %02d", math.min(6, f.index)), 860, 574, 23)
    text("DIRECT CONTROL", 1250, 574, 23, cyan)
    nvgEndFrame(vg)
end

--- Release the texture-render callback and its NanoVG context on shutdown.
function Cockpit:Destroy()
    self.receiver:UnsubscribeFromEvent(self.context, "NanoVGRender")
    nvgDelete(self.context)
end

return Cockpit
