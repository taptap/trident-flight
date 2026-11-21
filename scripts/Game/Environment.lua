-- Physical maritime environment. The native FFT surface drives both geometry and shading.
local Environment = {}
Environment.__index = Environment

--- Create the lighting, post processing and horizon-scale ocean in the supplied scene.
function Environment.Create(scene)
    local self = setmetatable({scene = scene}, Environment)
    renderer.hdrRendering = true
    renderer.materialQuality, renderer.textureQuality = QUALITY_MAX, QUALITY_HIGH
    renderer.textureAnisotropy = 16
    renderer.textureFilterMode = FILTER_ANISOTROPIC
    renderer.shadowQuality, renderer.shadowPCFSamples = SHADOWQUALITY_PCF_24BIT, 16
    renderer:SetShadowMapSize(4096)
    local node = scene:CreateChild("Environment")
    local zone = node:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(-80000, 80000)
    zone.envTextureDiffIntensity, zone.envTextureSpecIntensity = 1.6, 1.5
    zone.ambientColor = Color(0.16, 0.21, 0.27)
    zone:SetDepthFogEnable(false)
    zone.autoExposureEnabled = false
    zone.ssrEnabled, zone.ssrQuality, zone.ssrDenoiserEnabled = true, 4, true
    zone.ssgiEnabled, zone.ssgiQuality, zone.ssgiIntensity = true, 3, 0.7
    zone.ssaoRadius, zone.ssaoIntensity = 0.8, 1.6
    zone.motionBlurEnabled = false
    zone.bloomMode, zone.bloomUEIntensity, zone.bloomUEThreshold = BLOOM_MODE_UE, 0.22, 1.8
    zone.bloomUESizeScale = 3
    zone.tonemapMode = TONEMAP_MODE_ACES
    zone.tonemapExposure = 0.1
    self.zone = zone

    local sun = scene:CreateChild("Sun"):CreateComponent("Light")
    sun.lightType, sun.color, sun.brightness = LIGHT_DIRECTIONAL, Color(1.0, 0.98, 0.94), 7.0
    sun.castShadows = true
    sun.shadowCascade = CascadeParameters(60, 250, 1200, 0, 0.8)
    local elevation, azimuth = math.rad(32), math.rad(-35)
    sun.node.direction = -Vector3(math.sin(azimuth) * math.cos(elevation), math.sin(elevation),
        math.cos(azimuth) * math.cos(elevation))
    self.sun = sun
    local atmosphere = scene:CreateChild("Atmosphere"):CreateComponent("SkyAtmosphere")
    atmosphere.sunLight = sun
    -- This is an extinction coefficient per kilometer, not a multiplier of the default.
    atmosphere.mieScatteringScale = 0.0032
    atmosphere.aerialPerspectiveDistanceScale = 1.0
    atmosphere.traceSampleCountScale = 2.0
    local clouds = scene:CreateChild("Clouds"):CreateComponent("VolumetricCloud")
    clouds.layerBottomAltitude, clouds.layerHeight = 1700, 2800
    clouds.cloudGlobalCoverage, clouds.cloudGlobalScale = -0.18, 85000
    clouds.windVelocity = Vector2(9, 3)
    clouds.viewSampleCountScale, clouds.shadowSampleCountScale = 2.0, 1.5
    clouds.cloudShadowEnabled = true
    local capture = node:CreateComponent("SkyLightCapture")
    capture.captureSource, capture.includeClouds = SKY_CAPTURE_ATMOSPHERE, true
    capture.resolution, capture.minCaptureInterval = 256, 3.0
    capture:RequestCapture()
    self.capture = capture

    scene:CreateComponent("WaterWorld")
    local ocean = scene:CreateChild("Ocean")
    local geometry = ocean:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    local lines, outer, pos, step = {}, {}, 48, 1
    while pos < 24000 do
        pos = math.min(pos + step, 24000)
        outer[#outer + 1] = pos
        step = step * 1.14
    end
    for i = #outer, 1, -1 do lines[#lines + 1] = -outer[i] end
    for i = -48, 48 do lines[#lines + 1] = i end
    for _, value in ipairs(outer) do lines[#lines + 1] = value end
    local function vertex(x, z)
        geometry:DefineVertex(Vector3(lines[x], 0, lines[z]))
        geometry:DefineNormal(Vector3.UP)
        geometry:DefineTexCoord(Vector2(x / #lines, z / #lines))
    end
    for z = 1, #lines - 1 do
        for x = 1, #lines - 1 do
            vertex(x, z); vertex(x, z + 1); vertex(x + 1, z)
            vertex(x + 1, z); vertex(x, z + 1); vertex(x + 1, z + 1)
        end
    end
    geometry:Commit()
    local mesh = Model:new()
    assert(geometry:FillModel(mesh), "Ocean mesh generation failed")
    ocean:RemoveComponent(geometry)
    local drawable = ocean:CreateComponent("StaticModel")
    local waves = ocean:CreateComponent("FFTWaterSurface")
    waves:SetHeight(0)
    waves:SetPatchLength(512)
    waves:SetWindSpeed(10)
    waves:SetWindAngle(110)
    waves:SetFetch(70)
    waves:SetChoppiness(1.5)
    waves:SetSwell(0.12)
    local reach = waves:GetDisplacementBound() + 1
    local body = ocean:CreateComponent("WaterBody")
    body:SetBounds(Vector3(-25000, -1500, -25000), Vector3(25000, reach, 25000))
    mesh.boundingBox = BoundingBox(Vector3(-24000 - reach, -reach, -24000 - reach),
        Vector3(24000 + reach, reach, 24000 + reach))
    drawable.model = mesh
    drawable.material = cache:GetResource("Material", "Materials/Ocean.xml")
    drawable.castShadows = false
    self.ocean, self.waterMaterial = ocean, drawable.material
    return self
end

--- Keep the dense ocean grid under the aircraft without moving the world-space wave field.
function Environment:Update(position)
    self.ocean.position = Vector3(math.floor(position.x / 24) * 24, 0, math.floor(position.z / 24) * 24)
    local c = self.sun.color * self.sun.brightness
    local values = {
        scroll_time = Variant(self.scene:GetWaterWorld():GetTime()),
        wind_direction = Variant(Vector2(math.sin(math.rad(110)), math.cos(math.rad(110)))),
        wind_speed = Variant(10.0),
        sun_direction = Variant(-self.sun.node.worldDirection),
        sun_color = Variant(Vector3(c.r, c.g, c.b)),
        roughness_base = Variant(0.055),
        detail_strength = Variant(0.7),
        absorption = Variant(Vector3(0.42, 0.18, 0.11)),
        scattering = Variant(Vector3(0.004, 0.012, 0.018)),
        sss_strength = Variant(0.4),
        caustics_enabled = Variant(0.0),
        wave_fade = Variant(Vector4(self.ocean.position.x, self.ocean.position.z, 16000, 24000)),
    }
    for name, value in pairs(values) do self.waterMaterial:SetShaderParameter(name, value) end
end

return Environment
