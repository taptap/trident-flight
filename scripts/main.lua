-- Trident R06 flight trial, adapted from the 3D scene scaffold.
local UI = require("urhox-libs/UI")
local ThirdPersonCamera = require("urhox-libs/Camera/ThirdPersonCamera")
local Flight = require("Game.Flight")
local Aircraft = require("Game.Aircraft")
local Cockpit = require("Game.Cockpit")
local Environment = require("Game.Environment")
local Course = require("Game.Course")
local HUD = require("Game.HUD")
local scene_, aircraft_, cockpit_, environment_, course_, camera_, hud_
local flight_ = Flight.New()
local state_ = {gear = false, bay = false, photo = false, orbit = false, view = 1, help = false}
local accumulator_, yaw_, pitch_, zoom_ = 0.0, 125.0, 18.0, 1.0
local headYaw_, headPitch_ = 0.0, 0.0
local controls_ = {pitch = 0.0, roll = 0.0, yaw = 0.0, throttle = 0.0}
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

--- Dispatch both UI and device actions through the original trial state transitions.
local function action(name)
    if name == "restart" or (name == "start" and flight_.mode ~= "flight") then
        flight_:Reset("flight", name == "restart" or flight_.mode ~= "ready")
        state_.gear, state_.bay, state_.orbit, state_.view = false, false, false, 1
        accumulator_ = 0
    elseif name == "camera" then
        if flight_.mode == "flight" then state_.view = state_.view % 3 + 1
        else state_.orbit = not state_.orbit; state_.bay = false end
    elseif name == "gear" then state_.gear = not state_.gear
    elseif name == "bay" and flight_.mode ~= "flight" then state_.bay = not state_.bay
    elseif name == "photo" then state_.photo = not state_.photo
    elseif name == "help" then state_.help = not state_.help
    elseif name == "escape" then state_.photo, state_.help = false, false end
    if hud_ then hud_.manual:SetVisible(state_.help) end
end

--- Initialize scene ownership, the reusable chase camera, and the UI.
function Start()
    graphics.windowTitle = "TRIDENT / Black Emperor R06"
    input.mouseVisible, input.mouseMode = true, MM_ABSOLUTE
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    environment_ = Environment.Create(scene_)
    aircraft_ = Aircraft.Create(scene_)
    course_ = Course.Create(scene_)
    camera_ = ThirdPersonCamera.Create(scene_, {initialMode = "inspect", farClip = 65000, nearClip = 0.2,
        transitionSpeed = 5, modes = {
            inspect = {distance = 29, offset = Vector3(0, 1, 0), fov = 43},
            chase = {distance = 31, offset = Vector3(0, 2.8, 0), fov = 48},
            side = {distance = 34, offset = Vector3(0, 0.5, 0), fov = 42},
        }})
    -- Keep the camera and the aircraft-anchored cockpit as separate scene nodes.
    scene_:AddChild(camera_:GetNode())
    renderer:SetViewport(0, Viewport:new(scene_, camera_:GetCamera()))
    cockpit_ = Cockpit.Create(scene_, flight_)
    hud_ = HUD.Create(flight_, camera_:GetCamera(), action)
    aircraft_.node.position = flight_.position
    camera_:Update(1, aircraft_.node, yaw_, pitch_)
    course_:Update(flight_)
    environment_:Update(flight_.position)
    hud_:Update(1, state_)
    -- Local development inspection also lets integration tests exercise real actions and native components.
    Trident = {flight = flight_, state = state_, action = action, aircraft = aircraft_,
        cockpit = cockpit_, camera = camera_, scene = scene_, environment = environment_, hud = hud_}
    SubscribeToEvent("Update", "HandleUpdate")
    print("[Trident] R06 ready: six gates, three crosswinds, native FFT ocean and physical sky")
end

--- Release UI and cockpit texture resources when the project stops.
function Stop()
    if cockpit_ then cockpit_:Destroy() end
    UI.Shutdown()
end

local KEY_ACTIONS = {
    {KEY_RETURN, "start"}, {KEY_R, "restart"}, {KEY_C, "camera"}, {KEY_G, "gear"},
    {KEY_V, "bay"}, {KEY_P, "photo"}, {KEY_ESCAPE, "escape"}, {KEY_F1, "help"},
}
local function down(a, b) return (input:GetKeyDown(a) or (b and input:GetKeyDown(b))) and 1 or 0 end
local function deadzone(x) return math.abs(x) < 0.16 and 0 or (x > 0 and 1 or -1) * (math.abs(x) - 0.16) / 0.84 end

--- Read keyboard and SDL's standard controller mapping with an analog dead zone.
local function readInput()
    for _, pair in ipairs(KEY_ACTIONS) do if input:GetKeyPress(pair[1]) then action(pair[2]) end end
    controls_.pitch = down(KEY_W, KEY_UP) - down(KEY_S, KEY_DOWN)
    controls_.roll = down(KEY_D, KEY_RIGHT) - down(KEY_A, KEY_LEFT)
    controls_.yaw = down(KEY_E) - down(KEY_Q)
    controls_.throttle = down(KEY_LSHIFT, KEY_RSHIFT) - down(KEY_LCTRL, KEY_RCTRL)
    for i = 0, input.numJoysticks - 1 do
        local pad = input:GetJoystickByIndex(i)
        if pad:IsController() then
            controls_.pitch = clamp(controls_.pitch - deadzone(pad:GetAxisPosition(CONTROLLER_AXIS_LEFTY)), -1, 1)
            controls_.roll = clamp(controls_.roll + deadzone(pad:GetAxisPosition(CONTROLLER_AXIS_LEFTX)), -1, 1)
            controls_.yaw = clamp(controls_.yaw + deadzone(pad:GetAxisPosition(CONTROLLER_AXIS_RIGHTX)), -1, 1)
            controls_.throttle = clamp(controls_.throttle + pad:GetAxisPosition(CONTROLLER_AXIS_TRIGGERRIGHT)
                - pad:GetAxisPosition(CONTROLLER_AXIS_TRIGGERLEFT), -1, 1)
            for _, pair in ipairs({{CONTROLLER_BUTTON_A, "start"}, {CONTROLLER_BUTTON_B, "restart"},
                {CONTROLLER_BUTTON_X, "gear"}, {CONTROLLER_BUTTON_Y, "camera"}, {CONTROLLER_BUTTON_DPAD_UP, "bay"}}) do
                if pad:GetButtonPress(pair[1]) then action(pair[2]) end
            end
            break
        end
    end
end

--- Integrate at fixed 60 Hz, interpolate the airframe, then update the environment and camera.
function HandleUpdate(eventType, eventData)
    local dt = math.min(0.08, eventData["TimeStep"]:GetFloat())
    readInput()
    accumulator_ = accumulator_ + dt
    while accumulator_ >= 1 / 60 do flight_:Step(controls_); accumulator_ = accumulator_ - 1 / 60 end
    local node = aircraft_.node
    if flight_.mode == "flight" then
        node.position = flight_.previousPosition:Lerp(flight_.position, accumulator_ * 60)
        node.rotation = flight_.previousRotation:Slerp(flight_.rotation, accumulator_ * 60)
    else node.position, node.rotation = flight_.position, flight_.rotation end
    aircraft_:Update(dt, state_.gear, state_.bay, controls_)
    local inCockpit = flight_.mode == "flight" and state_.view == 2
    local looking = inCockpit and not state_.help and input:GetMouseButtonDown(MOUSEB_RIGHT)
    input.mouseMode = looking and MM_RELATIVE or MM_ABSOLUTE
    input.mouseVisible = not looking
    if looking then
        headYaw_ = clamp(headYaw_ + input.mouseMoveX * 0.25, -75, 75)
        headPitch_ = clamp(headPitch_ + input.mouseMoveY * 0.22, -35, 45)
    elseif inCockpit then
        local decay = math.exp(-dt * 7)
        headYaw_, headPitch_ = headYaw_ * decay, headPitch_ * decay
    else headYaw_, headPitch_ = 0, 0 end
    local pilotPosition = node.position + node.rotation * Vector3(0, 1.52, 5.3)
    if flight_.mode ~= "flight" then
        local mouse = input.mousePosition
        local overUI = UI.FindWidgetAt(mouse.x / UI.GetScale(), mouse.y / UI.GetScale())
        if input:GetMouseButtonDown(MOUSEB_RIGHT) or (input:GetMouseButtonDown(MOUSEB_LEFT) and not overUI) then
            yaw_ = yaw_ - input.mouseMoveX * 0.35
            pitch_ = clamp(pitch_ + input.mouseMoveY * 0.3, -35, 75)
            state_.orbit = false
        elseif state_.orbit then yaw_ = yaw_ + dt * 8 end
        zoom_ = clamp(zoom_ - input.mouseMoveWheel * 0.06, 0.6, 1.5)
        camera_:SetMode("inspect")
        camera_:Update(dt, node, yaw_, pitch_)
        camera_:GetCamera().fov = camera_:GetCurrentFOV() * zoom_
        node:SetDeepEnabled(true)
    else
        node:SetDeepEnabled(state_.view ~= 2)
        if state_.view == 2 then
            camera_:GetNode().position = pilotPosition
            camera_:GetNode().rotation = node.rotation * Quaternion(8 + headPitch_, headYaw_, 0)
            camera_:GetCamera().fov = 62
        else
            camera_:SetMode(state_.view == 3 and "side" or "chase")
            camera_:Update(dt, node, node.rotation.yawAngle + (state_.view == 3 and -125 or 0),
                state_.view == 3 and 12 or (node.rotation.pitchAngle + 9))
        end
    end
    cockpit_.gear = state_.gear
    cockpit_:Update(dt, inCockpit, pilotPosition, node.rotation, controls_)
    course_:Update(flight_)
    environment_:Update(node.position)
    hud_:Update(dt, state_)
end
