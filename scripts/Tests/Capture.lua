-- Native captures also include cockpit-left/right for inspecting the side consoles.
require("main")
local start, update = Start, HandleUpdate
local view, frames = "flight", 0
local ZERO = {pitch = 0, roll = 0, yaw = 0, throttle = 0}

function Start()
    start()
    for _, arg in ipairs(GetArguments()) do view = arg:match("^%-view=(.+)$") or view end
    local game = Trident
    if view == "ready" then
        -- Preserve the initial inspection state for menu captures.
    elseif view == "gear" then
        game.action("gear")
        game.action("bay")
    elseif view == "photo" or view == "detail" then game.action("photo")
    elseif view == "manual" then game.action("help")
    else
        game.action("start")
        local frames = view == "finish" and 1800 or 280
        local controls = (view == "crash" or view == "warning") and {pitch = -1, roll = 0, yaw = 0, throttle = -1} or ZERO
        for _ = 1, frames do
            game.flight:Step(controls)
            if view == "warning" and game.flight.position.y < 12 then break end
        end
        if view == "warning" then assert(game.flight.mode == "flight", "Warning must precede the sea impact") end
        if view:find("^cockpit") then game.action("camera") end
        if view == "cockpit-left" or view == "cockpit-right" then game.action("photo") end
        if view == "cockpit-bank" then
            for _ = 1, 65 do game.flight:Step({pitch = 0.3, roll = 0.65, yaw = 0.1, throttle = 1}) end
            game.action("gear")
            game.action("photo")
        end
        if view == "side" then game.action("camera"); game.action("camera") end
        game.flight.previousPosition, game.flight.previousRotation = game.flight.position, game.flight.rotation
        -- Freeze only this test instance after reaching the state through real simulation.
        game.flight.Step = function() end
    end
    game.hud:Update(1, game.state)
    print("[Capture] " .. view .. " at " .. game.flight.time .. " s; " .. game.flight.hits .. "/6")
end

function HandleUpdate(eventType, eventData)
    update(eventType, eventData)
    if view == "gear" then
        -- An underside inspection angle exposes the original gear and decorative bay joints.
        Trident.camera:Update(1, Trident.aircraft.node, 125, -12)
    elseif view == "detail" then
        Trident.camera:Update(1, Trident.aircraft.node, 125, 42)
        Trident.camera:GetCamera().fov = 30
    elseif view == "cockpit-left" or view == "cockpit-right" then
        Trident.camera:GetNode().rotation = Trident.aircraft.node.rotation * Quaternion(35, view == "cockpit-left" and -42 or 42, 0)
    end
    frames = frames + 1
    if frames == 90 then
        assert(Trident.environment.capture.ready, "Sky lighting capture did not finish")
        print("[Capture] Sky IBL ready; material quality " .. renderer.materialQuality)
        local f = Trident.flight
        print(string.format("[Capture] Instruments: speed=%d altitude=%d throttle=%d roll=%.2f pitch=%.2f gear=%s",
            math.floor(f.speed * 3.6 + 0.5), math.floor(f.position.y + 0.5), math.floor(f.throttle * 100 + 0.5),
            f.rotation.rollAngle, f.rotation.pitchAngle, tostring(Trident.state.gear)))
    end
end
