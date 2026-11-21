-- Reconstruct the original articulated GLB from rigid meshes and source pivot transforms.
local Data = require("Game.AircraftData")
local PropBuilder = require("urhox-libs/Geometry/PropBuilder")
local Aircraft = {}
Aircraft.__index = Aircraft
local function rotation(q) return Quaternion(q[4], -q[1], -q[2], q[3]) end

-- Add shallow cartridges aligned to sampled hull normals, retaining the original silhouette and joints.
local function addSurfaceHardware(centered)
    local b, materials = PropBuilder.new(), {}
    for name, params in pairs({skin = {0.075, 0.083, 0.087, 0.48, 0.22},
        recess = {0.008, 0.010, 0.012, 0.82, 0.0}, titanium = {0.19, 0.21, 0.22, 0.37, 0.78}}) do
        local m = Material:new()
        m:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        m:SetShaderParameter("MatDiffColor", Variant(Color(params[1], params[2], params[3])))
        m:SetShaderParameter("Roughness", Variant(params[4]))
        m:SetShaderParameter("Metallic", Variant(params[5]))
        materials[name] = m
    end
    -- x/y/z and outward normals are in the reflected GLB frame, before centering and yaw correction.
    local locations = {
        {1.5, 1.683272, 10.8, 0.686013, 0.724752, -0.064195, 0.38, 1.05, true},
        {2.3, 1.139607, 12.8, 0.573944, 0.818186, -0.034072, 0.48, 1.18, true},
        {1.2, 1.394522, 17.5, 0.355970, 0.917541, 0.177211, 0.36, 0.86, true},
        {4.0, 0.388214, 14.7, 0.217131, 0.976130, -0.004876, 0.72, 0.54, false},
    }
    for _, side in ipairs({-1, 1}) do
        for _, p in ipairs(locations) do
            local normal = Vector3(side * p[4], p[5], p[6]):Normalized()
            local w, d = p[7], p[8]
            b:Push(Vector3(side * p[1], p[2], p[3]) + normal * 0.014, Quaternion(Vector3.UP, normal))
            b:Add("skin", ChamferBoxGeometry(w, 0.022, d, 0.01))
            b:Add("recess", ChamferBoxGeometry(w - 0.06, 0.008, d - 0.08, 0.003):Translate(0, 0.014, 0))
            if p[9] then
                for i = 0, 10 do
                    b:Add("titanium", ChamferBoxGeometry(w - 0.10, 0.018, (d - 0.16) / 18, 0.005)
                        :ApplyQuaternion(Quaternion(24, Vector3.RIGHT)):Translate(0, 0.023, -(d - 0.16) / 2 + i * (d - 0.16) / 10))
                end
            else
                b:Add("skin", ChamferBoxGeometry(w - 0.073, 0.01, d - 0.093, 0.004):Translate(0, 0.019, 0))
                b:Add("titanium", ChamferBoxGeometry(0.12, 0.009, 0.028, 0.003):Translate(0, 0.026, d * 0.30))
            end
            for _, x in ipairs({-w / 2 + 0.024, w / 2 - 0.024}) do
                for _, z in ipairs({-d / 2 + 0.028, d / 2 - 0.028}) do
                    b:Add("titanium", CylinderGeometry(0.009, 0.009, 0.003, 12):Translate(x, 0.013, z))
                end
            end
            b:Pop()
        end
    end
    PropBuilder.Attach(centered:CreateChild("SurfaceHardware"), b:Build(), materials)
end

--- Load all original components, preserving animation pivots and material assignments.
function Aircraft.Create(scene)
    local self = setmetatable({nodes = {}, materials = {}, gear = 0.0, bay = 0.0}, Aircraft)
    self.node = scene:CreateChild("R06")
    local orientation = self.node:CreateChild("ModelOrientation")
    orientation.rotation = Quaternion(0, 180, 0)
    local centered = orientation:CreateChild("CenteredModel")
    centered.position = Vector3(-Data.center[1], -Data.center[2], Data.center[3])
    for i, source in ipairs(Data.materials) do
        local pbr = source.pbrMetallicRoughness or {}
        local color = pbr.baseColorFactor or {0.5, 0.5, 0.5, 1}
        local emission = source.emissiveFactor or {0, 0, 0}
        local material = Material:new()
        assert(material:SetSurfaceShader("Shaders/Airframe.shader"))
        local marking = source.name:find("painted identity", 1, true) or source.name:find("secondary airframe", 1, true)
        if marking then
            material.depthBias = BiasParameters(-0.00001, -1.0)
        end
        local roughness = pbr.roughnessFactor or 0.5
        local skin = source.name:find("Matte graphite", 1, true) ~= nil
        self.materials[i] = {material = material, color = Vector4(color[1], color[2], color[3], 1),
            roughness = math.max(0.12, roughness * (skin and 0.65 or 0.82)), metal = pbr.metallicFactor or 0.0,
            coat = source.name == "Neutral smoked canopy" and 0.92 or (skin and 0.12 or 0.0),
            detail = skin and 1.0 or 0.0, castShadows = not marking and not source.name:find("lens", 1, true),
            emission = Vector3(emission[1], emission[2], emission[3]) * 8}
    end
    for i, source in ipairs(Data.nodes) do self.nodes[i] = centered:CreateChild(source.name or ("Part" .. i)) end
    for i, source in ipairs(Data.nodes) do
        local node = self.nodes[i]
        -- AddChild preserves local TRS; SetParent preserves world TRS and corrupts imported pivots.
        for _, child in ipairs(source.children or {}) do node:AddChild(self.nodes[child + 1]) end
        local t, s = source.translation or {0, 0, 0}, source.scale or {1, 1, 1}
        node.position, node.scale = Vector3(t[1], t[2], -t[3]), Vector3(s[1], s[2], s[3])
        node.rotation = rotation(source.rotation or {0, 0, 0, 1})
        if source.mesh then
            local model = node:CreateComponent("StaticModel")
            model.model = cache:GetResource("Model", string.format("Models/R06/Part%02d.mdl", source.mesh))
            assert(model.model, "Missing aircraft mesh " .. source.mesh)
            local castsShadow = false
            for j, primitive in ipairs(Data.meshes[source.mesh + 1].primitives) do
                local material = self.materials[(primitive.material or 0) + 1]
                model:SetMaterial(j - 1, material.material)
                castsShadow = castsShadow or material.castShadows
            end
            model.castShadows = castsShadow
        end
    end
    addSurfaceHardware(centered)
    self:Update(0, false, false, {pitch = 0, roll = 0, yaw = 0})
    return self
end

--- Smoothly deploy the original landing gear and bay poses without changing flight physics.
function Aircraft:Update(dt, gear, bay, controls)
    local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
    local function smooth(x) x = clamp(x, 0, 1); return x * x * (3 - 2 * x) end
    self.gear = self.gear + clamp((gear and 1 or 0) - self.gear, -dt / 1.45, dt / 1.45)
    self.bay = self.bay + clamp((bay and 1 or 0) - self.bay, -dt / 0.8, dt / 0.8)
    for id, pose in pairs(Data.poses) do
        local node = self.nodes[tonumber(id) + 1]
        local name, amount = node.name, nil
        if name:find("^GearDoor") then amount = smooth(self.gear * 3.2)
        elseif name:find("^Gear") then amount = smooth((self.gear - 0.28) / 0.72)
        elseif name:find("^EmptyBay") then amount = smooth(self.bay) end
        if amount then node.rotation = rotation(pose.closed):Slerp(rotation(pose.open), amount)
        else
            local radians = name:find("^TailTrim") and controls.yaw * 0.21 or
                (controls.pitch * 0.24 + controls.roll * 0.25 * (name:find("_L$") and 1 or -1))
            node.rotation = rotation(pose.closed) * Quaternion(-math.deg(radians), Vector3.RIGHT)
        end
    end
    -- Asynchronously generated surface shaders can restore defaults; reapply authored values.
    for _, m in ipairs(self.materials) do
        m.material:SetShaderParameter("coating", Variant(m.color))
        m.material:SetShaderParameter("base_roughness", Variant(m.roughness))
        m.material:SetShaderParameter("metal", Variant(m.metal))
        m.material:SetShaderParameter("coat", Variant(m.coat))
        m.material:SetShaderParameter("skin_detail", Variant(m.detail))
        m.material:SetShaderParameter("navigation_light", Variant(m.emission))
    end
end

return Aircraft
