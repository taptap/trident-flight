-- Golden trajectories were measured independently in the original cannon-es 0.20 H5.
local Flight = require("Game.Flight")
local ZERO = {pitch = 0, roll = 0, yaw = 0, throttle = 0}
local function near(actual, expected, tolerance, name)
    assert(math.abs(actual - expected) <= tolerance, name .. ": " .. actual .. " ~= " .. expected)
end
local function position(f, p)
    near(f.position.x, p[1], 0.03, "x")
    near(f.position.y, p[2], 0.03, "y")
    near(f.position.z, p[3], 0.03, "z")
end

--- Exercise the public flight model against reference trajectories, controls and gate boundaries.
function Start()
    local ok, err = pcall(function()
        local goldens = {
            {22.1666666667, 3, {4.4211425958, 64.1357185038, 942.1667078879}},
            {21.8833333333, 3, {-6.8479339328, 60.0240268537, 942.4831833568}},
            {22.95, 5, {14.4662104250, 72.5839283500, 942.3149309584}},
        }
        for wind, expected in ipairs(goldens) do
            local f = Flight.New()
            f.wind = wind
            f:Reset("flight", false)
            for _ = 1, 1800 do f:Step(ZERO) end
            assert(f.mode == "finish" and f.hits == expected[2], "Crosswind result " .. wind)
            near(f.time, expected[1], 0.00001, "Completion time")
            position(f, expected[3])
            print(string.format("[TEST] Wind %d: %.5fs, %d/6, position %s", wind, f.time, f.hits, tostring(f.position)))
        end
        local f = Flight.New()
        f:Reset("flight", false)
        for _ = 1, 360 do f:Step({pitch = 0.3, roll = -0.2, yaw = 0.1, throttle = 0.5}) end
        assert(f.mode == "flight")
        position(f, {-98.7503160040, 130.9319780864, 103.6450042112})
        near(f.throttle, 1, 0.000001, "Throttle upper limit")
        f:Reset("flight", false)
        for _ = 1, 180 do f:Step({pitch = -1, roll = 0, yaw = 0, throttle = -1}) end
        position(f, {2.7902512086, 26.9859729436, 5.1802433253})
        for _ = 1, 360 do f:Step({pitch = -1, roll = 0, yaw = 0, throttle = -1}) end
        -- This port stops at the original center-height cutoff, without Cannon's brief box/sea bounce.
        assert(f.mode == "crash" and f.position.y < 1.6, "Sea impact terminates flight")
        assert(f.time > 4 and f.time < 4.3, "Impact follows the reference dive")
        near(f.throttle, 0, 0.000001, "Throttle lower limit")
        for _, x in ipairs({27.98, 28.02}) do
            f:Reset("flight", false)
            f.position = Vector3(x, 75, 94.9)
            f:Step(ZERO)
            assert(f.index == 2 and f.outcomes[1] == (x < 28), "Gate radius boundary")
        end
        f:Reset("ready", true)
        local p = f.position
        f:Step(ZERO)
        assert(f.mode == "ready" and f.time == 0 and f.position == p and f.wind == 2, "Reset and ready freeze")
    end)
    if not ok then print("[TEST] " .. tostring(err)) end
    print(ok and "[TEST] RESULT PASS" or "[TEST] RESULT FAIL")
    engine:Exit()
end
