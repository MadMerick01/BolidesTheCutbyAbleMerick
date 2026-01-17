local M = {}
M.type = "auxiliary"
M.defaultOrder = 100

local random = math.random
local min = math.min
local max = math.max

local ammoTag = nil
local barrelNodeFront = nil
local barrelNodeRear = nil
local fireInterval = 0.1
local muzzleVel = 300
local accuracy = 3
local recoil = 0

local thrust = 0
local maxSpeed = 200

local impactAcceleration = 10000
local minSpeed = 10
local explosionRadius = 0
local explosionForce = 50

local projectileLength = 0
local projectileWidth = 0.05
local projectileColor = color(150, 150, 150, 255)

local tracerEveryXRounds = 1
local tracerLength = 0.01
local tracerWidth = 0.02
local tracerColor = color(255, 180, 0, 255)

local fireElectric = "fireweapons"
local barrelSpinElectric = "barrelspin"
local barrelSpinSpeed = 1000
local barrelSpinSlowdown = 1000

local singleShotSound = nil
local impactSound = nil
local impactSoundVolume = 5
local muzzleFlash = true
local rocketEffect = false

local barrelFrontId = nil
local barrelRearId = nil


local ammoCount = 0
local ammoNodes = {}
local ammoIndex = 1
local fireTimer = 0

local activeNodes = {}
local projectileVel = {}
local projectileDir = {}

local tracerCounter = 0
local tracerNodes = {}

local fireSoundLoopId = nil
local fireStartSoundId = nil
local fireStopSoundId = nil
local fireSoundPlaying = false

local barrelAV = 0

-- Credit for explosion function to me262 mod author, slightly modified by stefan750
-- position in game coordinates, radius1 is up to which radius the full force is applied, then a linear dropoff to radius2, no force after radius2
local function createExplosionAtPosition(position, radius, force, directionInversionCoef)
    local explosionString = string.format([[
        local localPosition = vec3(%f,%f,%f) - obj:getPosition()
        local radius1 = %f
        local radius2 = %f
        
        local boundLen = vec3(obj:getInitialWidth() + radius2, obj:getInitialLength() + radius2, obj:getInitialHeight() + radius2):squaredLength()

        if localPosition:squaredLength() <= boundLen then
            local nodeCount = #v.data.nodes
            local abs = math.abs
            local random = math.random
            for i = 0, nodeCount do
                local node = v.data.nodes[i]
                local nodePos = obj:getNodePosition(node.cid)
                local distanceVec = nodePos - localPosition
                local distance = abs(distanceVec:length())
                if distance <= radius2 then
                    local force = %f * 2000
                    local dirInversion = fsign(random() - %f) --~30percent inverted
                    local forceAdjusted = force * clamp(-1 * (distance - radius1) / (radius2 - radius1) + 1, 0, 1)
                    obj:applyForceVector(node.cid, distanceVec:normalized() * dirInversion * forceAdjusted)
                    --print(tostring(objectId)..": "..node.name.." -> "..forceAdjusted)
                end
            end
        end
        ]], position.x, position.y, position.z, radius*0.5, radius, force, directionInversionCoef or 0.3)
    BeamEngine:queueAllObjectLua(explosionString)
end

local function createExplosionAtNode(centerNode, radius, force)
    local position = obj:getPosition() + obj:getNodePosition(centerNode)
    createExplosionAtPosition(position, radius, force)

    -- Explosion particle effect (adapted from fire.lua game code)
    --small flames for low intensity fire
    obj:addParticleByNodesRelative(centerNode, centerNode, 0, 25, 0.1, 3)

    if radius >= 1 then
        --medium flames for medium intensity fire
        obj:addParticleByNodesRelative(centerNode, centerNode, 0, 27, 0.2, 3)

        if radius >= 2 then
            --large flames for high-intensity fire
            obj:addParticleByNodesRelative(centerNode, centerNode, 0, 29, 0.3, 3)

            if radius >= 5 then
                obj:addParticleByNodesRelative(centerNode, centerNode, 0, 31, 0.5, 10)
                --huge smoke puff for explosions
                obj:addParticleByNodesRelative(centerNode, centerNode, 0, 32, 0, 1)
                --spray of sparks
                obj:addParticleByNodesRelative(centerNode, centerNode, 0, 9, 0.5, 30)
            end
        end
    end
end

local function reset(jbeamData)
    ammoIndex = 1
    fireTimer = 0

    activeNodes = {}
    projectileVel = {}
    projectileDir = {}

    tracerCounter = 0
    tracerNodes = {}

    barrelAV = 0

    electrics.values[barrelSpinElectric] = 0
    electrics.values[fireElectric] = 0
end

local function init(jbeamData)
    fireInterval = jbeamData.fireRate and (60/jbeamData.fireRate) or fireInterval
    muzzleVel = jbeamData.muzzleVel or muzzleVel
    accuracy = jbeamData.accuracy or accuracy
    recoil = jbeamData.recoil or recoil
    
    thrust = jbeamData.thrust or thrust
    maxSpeed = jbeamData.maxSpeed or maxSpeed

    explosionRadius = jbeamData.explosionRadius or explosionRadius
    explosionForce = jbeamData.explosionForce or explosionForce
    impactAcceleration = jbeamData.impactAcceleration or impactAcceleration
    minSpeed = jbeamData.minSpeed or minSpeed
    
    projectileLength = jbeamData.projectileLength or projectileLength
    projectileWidth = jbeamData.projectileWidth or projectileWidth
    projectileColor = jbeamData.projectileColor and color(jbeamData.projectileColor[1] or 0, jbeamData.projectileColor[2] or 0, jbeamData.projectileColor[3] or 0, jbeamData.projectileColor[4] or 255) or projectileColor
    
    tracerEveryXRounds = jbeamData.tracerEveryXRounds or tracerEveryXRounds
    tracerLength = jbeamData.tracerLength or tracerLength
    tracerWidth = jbeamData.tracerWidth or tracerWidth
    tracerColor = jbeamData.tracerColor and color(jbeamData.tracerColor[1] or 0, jbeamData.tracerColor[2] or 0, jbeamData.tracerColor[3] or 0, jbeamData.tracerColor[4] or 255) or tracerColor
    
    fireElectric = jbeamData.fireElectric or fireElectric
    
    barrelSpinElectric = jbeamData.barrelSpinElectric or barrelSpinElectric
    barrelSpinSpeed = jbeamData.barrelSpinSpeed or barrelSpinSpeed
    barrelSpinSlowdown = jbeamData.barrelSpinSlowdown or barrelSpinSlowdown
    
    singleShotSound = jbeamData.singleShotSound or singleShotSound
    impactSound = jbeamData.impactSound or impactSound
    impactSoundVolume = jbeamData.impactSoundVolume or impactSoundVolume
    
    muzzleFlash = jbeamData.muzzleFlash or muzzleFlash
    rocketEffect = jbeamData.rocketEffect or rocketEffect

    ammoTag = jbeamData.ammoTag
    barrelNodeFront = jbeamData.barrelNodeFront
    barrelNodeRear = jbeamData.barrelNodeRear

    if not ammoTag then
        log('E', "407guns.init", "ammoTag not defined!")
    end
    if not barrelNodeFront then
        log('E', "407guns.init", "barrelNodeFront not defined!")
    end
    if not barrelNodeRear then
        log('E', "407guns.init", "barrelNodeRear not defined!")
    end

    ammoCount = 0
    ammoNodes = {}
    for _, n in pairs(v.data.nodes) do
        if n.name == barrelNodeFront then
            barrelFrontId = n.cid
        end
        if n.name == barrelNodeRear then
            barrelRearId = n.cid
        end
        
        if n.tag == ammoTag then
            ammoCount = ammoCount + 1
            ammoNodes[ammoCount] = n.cid
        end
    end

    reset(jbeamData)
end

local function initSounds(jbeamData)
    if jbeamData.fireSoundLoop then
        fireSoundLoopId = obj:createSFXSource2(jbeamData.fireSoundLoop, "AudioDefaultLoop3D", "", barrelFrontId, 0)
        obj:setVolume(fireSoundLoopId, 1)
    end

    if jbeamData.fireStartSound then
        fireStartSoundId = obj:createSFXSource2(jbeamData.fireStartSound, "AudioDefault3D", "", barrelFrontId, 0)
        obj:setVolume(fireStartSoundId, 1)
    end

    if jbeamData.fireStopSound then
        fireStopSoundId = obj:createSFXSource2(jbeamData.fireStopSound, "AudioDefault3D", "", barrelFrontId, 0)
        obj:setVolume(fireStopSoundId, 1)
    end
end

local function update(dt)
	
    -- Projectile update
    for n, _ in pairs(activeNodes) do
        if activeNodes[n] < 1 then
            activeNodes[n] = activeNodes[n] + 1
            goto continue
        end
        
        local currentVel = obj:getNodeVelocityVector(n)
        local lastVel = projectileVel[n]
        local acc = (currentVel-lastVel)/dt

        projectileVel[n] = currentVel

        -- If projectile hit something (acceleration high), or the speed is too low, explode or deactivate it
        if acc:squaredLength() > impactAcceleration*impactAcceleration or currentVel:squaredLength() < minSpeed*minSpeed then
            if impactSound then
                sounds.playSoundOnceAtNode(impactSound, n, impactSoundVolume, 1, 0, 0)
            end

            if explosionRadius > 0 then
                createExplosionAtNode(n, explosionRadius, explosionForce)
            end
            
            activeNodes[n] = nil
            tracerNodes[n] = nil
            projectileVel[n] = nil
        end

        -- Apply thrust force
        if thrust > 0 then
            local dir = projectileDir[n]
            local speed = currentVel:dot(dir)
            local force = clamp(maxSpeed - speed, -thrust*dt, thrust*dt)

            obj:applyForceVector(n, force*dir*obj:getNodeMass(n)*2000)
        end

        ::continue::
    end
    
    -- Firing
    if electrics.values[fireElectric] and electrics.values[fireElectric] > 0.5 then
        fireTimer = fireTimer + dt

        -- Fire a projectile
        while(fireTimer >= fireInterval) do
            ammoIndex = (ammoIndex % ammoCount) + 1
            local n = ammoNodes[ammoIndex]
            local barrelPosFront = obj:getNodePosition(barrelFrontId)
            local barrelPosRear = obj:getNodePosition(barrelRearId)
            local barrelDir = (barrelPosFront - barrelPosRear):normalized()

            --obj.debugDrawProxy:drawNodeVector3d(0.1, barrelFrontId, barrelDir, color(255, 0, 0, 255))

            projectileVel[n] = obj:getNodeVelocityVector(n)
            activeNodes[n] = 0
            projectileDir[n] = barrelDir

            local newVel = barrelDir*muzzleVel + vec3(random() - 0.5, random() - 0.5, random() - 0.5)*accuracy

            -- Shoot node
            obj:setNodePosition(n, barrelPosFront)
            obj:applyForceVector(n, (newVel - projectileVel[n])*obj:getNodeMass(n)*2000)

            projectileVel[n] = newVel

            obj:applyForce(barrelFrontId, barrelRearId, recoil*obj:getNodeMass(barrelFrontId)*1000)
            obj:applyForce(barrelRearId, barrelFrontId, -recoil*obj:getNodeMass(barrelRearId)*1000)
            
            -- Muzzle flash particles
            if muzzleFlash then
                obj:addParticleByNodesRelative(barrelFrontId, barrelRearId, -15, 61, 0, 1)
                obj:addParticleByNodesRelative(barrelFrontId, barrelRearId, -10, 62, 0, 1)
                obj:addParticleByNodesRelative(barrelFrontId, barrelRearId, -20, 63, 0, 1)
                obj:addParticleByNodesRelative(barrelFrontId, barrelRearId, -8, 64, 0, 1)
                obj:addParticleByNodesRelative(barrelFrontId, barrelRearId, -12, 65, 0, 1)

                obj:addParticleByNodesRelative(barrelFrontId, barrelRearId, -5, 41, 0, 1)
                obj:addParticleByNodesRelative(barrelFrontId, barrelRearId, -3, 41, 0, 1)
            end

            -- Shot sound effect
            if singleShotSound then
                sounds.playSoundOnceFollowNode(singleShotSound, barrelFrontId, 1, 1, 0, 0)
            end

            -- Attach tracers
            tracerCounter = tracerCounter + 1
            if tracerCounter >= tracerEveryXRounds and tracerLength > 0 then
                tracerNodes[n] = 0
                tracerCounter = 0
            end

            fireTimer = fireTimer - fireInterval
        end

        -- Start sound effects
        if not fireSoundPlaying then
            if fireStartSoundId then
                obj:cutSFX(fireStartSoundId)
                obj:playSFX(fireStartSoundId)
            end
            
            if fireSoundLoopId then
                obj:setVolumePitchCT(fireSoundLoopId, 1, 0.95 + random()*0.1, 0, 0) -- to stop sound artifacts from multiple guns
                obj:playSFX(fireSoundLoopId)
            end
            fireSoundPlaying = true
        end

        -- Set barrel spin speed
        barrelAV = barrelSpinSpeed
    
    -- Stop Firing
    else
        fireTimer = min(fireTimer + dt, fireInterval)

        -- Stop sound effects
        if fireSoundPlaying then
            if fireSoundLoopId then
                obj:cutSFX(fireSoundLoopId)
                obj:stopSFX(fireSoundLoopId)
            end

            if fireStopSoundId then
                obj:cutSFX(fireStopSoundId)
                obj:playSFX(fireStopSoundId)
            end
            fireSoundPlaying = false
        end

        -- Slowly spin down barrel
        barrelAV = max(barrelAV - barrelSpinSlowdown*dt, 0)
    end

    -- Update barrel rotation
    electrics.values[barrelSpinElectric] = (electrics.values[barrelSpinElectric] + barrelAV*dt) % 360
end

local function updateGFX(dt)
	-- Draw projectiles
    for n, t in pairs(activeNodes) do
        if projectileLength > 0 then
            obj.debugDrawProxy:drawNodeVector3d(projectileWidth, n, projectileDir[n]*projectileLength, projectileColor)
        end

        if rocketEffect then
            obj:addParticleByNodesRelative(n, n, 0, 81, 0.01, 1)
            obj:addParticleByNodesRelative(n, n, 0, 80, 0.01, 1)
        end
    end

    -- Draw tracers
    for n, l in pairs(tracerNodes) do
        if tracerLength > 0 then
            obj.debugDrawProxy:drawNodeVector3d(tracerWidth, n, -projectileVel[n]*tracerLength*l, tracerColor)

            if tracerNodes[n] < 1 then
                tracerNodes[n] = min(l + dt/tracerLength, 1)
            end
        end
    end
end

-- public interface
M.reset      = reset
M.init       = init
M.initSounds = initSounds
M.update     = update
M.updateGFX  = updateGFX

return M