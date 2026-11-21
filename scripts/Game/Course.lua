local Flight = require("Game.Flight")
local Course = {}
Course.__index = Course

--- Build thin luminous navigation rings at the original six gate positions and radii.
function Course.Create(scene)
    local self = setmetatable({rings = {}}, Course)
    for i, spec in ipairs(Flight.GATES) do
        local node = scene:CreateChild("Gate" .. i)
        node.position = Vector3(spec[1], spec[2], spec[3])
        local mesh = node:CreateComponent("StaticModel")
        mesh.model = TorusGeometry(spec[4], 0.3, 8, 160):ToModel()
        local material = Material:new()
        material:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        material:SetShaderParameter("MatDiffColor", Variant(Color(0.4, 0.7, 0.8)))
        mesh.material = material
        self.rings[i] = {node = node, material = material}
    end
    return self
end

--- Hide crossed rings; highlight only the next gate without changing its collision radius.
function Course:Update(flight)
    for i, ring in ipairs(self.rings) do
        ring.node:SetDeepEnabled(flight.mode == "flight" and i >= flight.index)
        ring.material:SetShaderParameter("MatDiffColor", Variant(i == flight.index and Color(2.6, 1.8, 0.65) or Color(0.15, 0.35, 0.4)))
    end
end

return Course
