-- R06's original aerodynamic model, integrated at 60 Hz independently of rendering.
-- The original game only collides with the sea, so no general collision solver is needed.
-- Box inertia, exponential damping and semi-implicit integration match the H5 implementation.
local Flight = {}
Flight.__index = Flight

Flight.GATES = {
    {0, 75, 95, 28}, {14, 81, 255, 29}, {34, 90, 425, 31},
    {6, 103, 595, 32}, {-28, 93, 765, 33}, {-8, 80, 942, 32},
}
local WINDS = {{2.6, 0, 0}, {-4.6, 0, 0.8}, {6.4, 0, -1.4}}
local STEP = 1 / 60
local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

--- Create a stationary preview with the original airframe's initial flight state.
function Flight.New()
    local self = setmetatable({wind = 1}, Flight)
    self:Reset("ready", false)
    return self
end

--- Reset the trial. Advance cycles the original three crosswind conditions.
function Flight:Reset(mode, advance)
    if advance then self.wind = self.wind % #WINDS + 1 end
    self.mode = mode or "flight"
    self.time, self.index, self.hits = 0, 1, 0
    self.throttle, self.spool, self.speed, self.aoa = 0.54, 0.54, 47, 0
    self.position, self.velocity = Vector3(0, 75, -95), Vector3(0, 0, 47)
    self.rotation, self.angular = Quaternion(), Vector3()
    self.outcomes, self.pulse, self.pulseEnd = {}, "", 0
    self.previousPosition, self.previousRotation = self.position, self.rotation
end

--- Advance one fixed step with normalized pitch, roll, yaw and throttle inputs.
function Flight:Step(c)
    if self.mode ~= "flight" then return end
    local q = self.rotation
    local front, right, up = q * Vector3.FORWARD, q * Vector3.RIGHT, q * Vector3.UP
    local wind = WINDS[self.wind]
    local flow = self.velocity - Vector3(wind[1], wind[2], wind[3])
    local speed = flow:Length()
    local forward, side = flow:DotProduct(front), flow:DotProduct(right)
    local aoa = math.atan(-flow:DotProduct(up), math.max(0.15, forward))
    local air = math.min(speed * speed, 16000)
    local efficiency = 1 - 0.78 * clamp((math.abs(aoa) - 0.23) / 0.47, 0, 1)
    local force = Vector3(0, -98.1, 0)
    if speed > 0.01 then
        local direction = flow / speed
        local lift = clamp((0.044 + 0.34 * aoa) * air * efficiency, -280, 390)
            * clamp(forward / 7, 0, 1)
        force = force + direction:CrossProduct(right) * lift
            - direction * (air * (0.014 + 0.17 * aoa * aoa) + math.abs(side) * 0.23)
            - right * (side * 2.2)
    end
    self.throttle = clamp(self.throttle + c.throttle * 0.49 * STEP, 0, 1)
    self.spool = self.spool + (self.throttle - self.spool) * STEP * 2.2
    force = force + front * (self.spool * 63)
    local angular = self.angular
    local authority = clamp(speed / 45, 0.34, 1.45)
    local assist = math.abs(c.roll) < 0.035 and up.y > 0.18 and right.y * 39 or 0
    local torque = right * (-c.pitch * 124 * authority - angular:DotProduct(right) * 95 + clamp(aoa, -0.9, 0.9) * 49)
        + up * (c.yaw * 138 * authority - angular:DotProduct(up) * 83 - right.y * 57 + side * 3.2)
        + front * (-c.roll * 123 * authority - angular:DotProduct(front) * 68 - assist)
    local localTorque = q:Inverse() * torque
    local acceleration = q * Vector3(localTorque.x / (10 / 3 * (0.8 ^ 2 + 4 ^ 2)),
        localTorque.y / (10 / 3 * (4.5 ^ 2 + 4 ^ 2)),
        localTorque.z / (10 / 3 * (4.5 ^ 2 + 0.8 ^ 2)))
    self.previousPosition, self.previousRotation = self.position, q
    self.velocity = self.velocity * (0.991 ^ STEP) + force * (STEP / 10)
    self.angular = angular * (0.92 ^ STEP) + acceleration * STEP
    self.position = self.position + self.velocity * STEP
    local w = self.angular
    self.rotation = (q + (Quaternion(0, w.x, w.y, w.z) * q) * (STEP * 0.5)):Normalized()
    self.time, self.speed, self.aoa = self.time + STEP, speed, aoa
    if self.position.y < 1.6 then
        self.mode, self.pulse = "crash", "试飞中止 · 撞水"
        return
    end
    local gate = Flight.GATES[self.index]
    if gate and self.previousPosition.z < gate[3] and self.position.z >= gate[3] then
        local t = (gate[3] - self.previousPosition.z) / (self.position.z - self.previousPosition.z)
        local crossing = self.previousPosition:Lerp(self.position, t)
        local hit = (crossing.x - gate[1]) ^ 2 + (crossing.y - gate[2]) ^ 2 <= gate[4] ^ 2
        self.outcomes[self.index] = hit
        self.hits = self.hits + (hit and 1 or 0)
        self.pulse, self.pulseEnd = hit and "航门通过" or "错过航门", self.time + 1.3
        self.index = self.index + 1
        if self.index > #Flight.GATES then self.mode = "finish" end
    end
end

return Flight
