-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}



--main variables
local agentygun_currentbullet_num
local agentygun_timeBetweenBullets
local agentygun_canShoot --boolean
local agentygun_bulletsLeft
local agentygun_bulletsLeftPercentage
local agentygun_breakBeam
local agentygun_isBroken --boolean
local agentygun_currentBeltSection_num
local agentygun_requiredBeltSectionLength
local agentygun_beltDetachBeam
local agentygun_isBeltDetached --boolean
local reloading
local playervelocity
local agentygun_rpgboom
local explosionlocation
local agentygun_rpgreset
local agentygun_bulletvel
local explosionlocationset
local agentygun_bulletsfired
local agentygun_rpghit


--from jbeamData
local agentygun_ammo
local agentygun_shoot_delay
local agentygun_guntype
local agentygun_bulletMass
local agentygun_decreaseAmmoWeightOnShooting --boolean
local agentygun_bulletMassInAmmo
local agentygun_breakable --boolean
local agentygun_breakBeamName
local agentygun_hasBelt --boolean
local agentygun_bulletsPerBeltSection
local agentygun_beltDetachable --boolean
local agentygun_beltDetachBeamName
local agentygun_hasSecondaryGun --boolean
local agentygun_simplifiedMode --boolean
local agentygun_magsize
local agentygun_reloadtime
local agentygun_BulletAcc2
local agentygun_rpg
local agentygun_isInfinite
--variables for nodes
local agentygun_gunSoundNode --gun sounds location
local agentygun_fireParticleNodeInner --shoot particles location
local agentygun_fireParticleNodeOuter --shoot particles direction
local agentygun_ammoWeightStorageNode --stores the weight of the gun's ammo, more useful for flamethrower since the machine gun bullets are light
local agentygun_gunSoundNode2 --gun sounds location
local agentygun_fireParticleNodeInner2 --shoot particles location
local agentygun_fireParticleNodeOuter2 --shoot particles direction
local agentygun_explosionNode


--variables for names of the nodes from JbeamData
local agentygun_gunSoundNodeID
local agentygun_fireParticleNodeInnerID
local agentygun_fireParticleNodeOuterID
local agentygun_ammoWeightStorageNodeID
local agentygun_gunSoundNodeID2
local agentygun_fireParticleNodeInnerID2
local agentygun_fireParticleNodeOuterID2
local agentygun_explosionNodeID


local function init(jbeamData)

  --get jbeamData
  agentygun_ammo = jbeamData.agentygun_ammo or 100
  agentygun_shoot_delay = jbeamData.agentygun_shoot_delay or 0.075
  agentygun_guntype = jbeamData.agentygun_guntype or "Machinegun"
  agentygun_bulletMass = jbeamData.agentygun_bulletMass or 2.5
  agentygun_gunSoundNodeID = jbeamData.agentygun_gunSoundNode or "agentygun2"
  agentygun_decreaseAmmoWeightOnShooting = jbeamData.agentygun_decreaseAmmoWeightOnShooting or false
  agentygun_fireParticleNodeInnerID = jbeamData.agentygun_fireParticleNodeInner or "agentygun2"
  agentygun_fireParticleNodeOuterID = jbeamData.agentygun_fireParticleNodeOuter or "agentygun1"
  agentygun_ammoWeightStorageNodeID = jbeamData.agentygun_ammoWeightStorageNode or "agentygun_ammo"
  agentygun_bulletMassInAmmo = jbeamData.agentygun_bulletMassInAmmo or 2.5
  agentygun_breakable = jbeamData.agentygun_breakable or false
  agentygun_breakBeamName = jbeamData.agentygun_breakBeamName or "agentygun_broken"
  agentygun_hasBelt = jbeamData.agentygun_hasBelt or false
  agentygun_bulletsPerBeltSection = jbeamData.agentygun_bulletsPerBeltSection or 10
  agentygun_beltDetachable = jbeamData.agentygun_beltDetachable or false
  agentygun_beltDetachBeamName = jbeamData.agentygun_beltDetachBeamName or "agentygun_belt_detach"
  agentygun_hasSecondaryGun = jbeamData.agentygun_hasSecondaryGun or false
  agentygun_gunSoundNodeID2 = jbeamData.agentygun_gunSoundNode2 or "agentygun2r"
  agentygun_fireParticleNodeInnerID2 = jbeamData.agentygun_fireParticleNodeInner2 or "agentygun2r"
  agentygun_fireParticleNodeOuterID2 = jbeamData.agentygun_fireParticleNodeOuter2 or "agentygun1r"
  agentygun_simplifiedMode = jbeamData.agentygun_simplifiedMode or false
  agentygun_magsize = jbeamData.agentygun_magsize or 1000
  agentygun_reloadtime = jbeamData.agentygun_reloadtime or 3
  agentygun_rpg = jbeamData.agentygun_rpg or false
  agentygun_explosionNodeID = jbeamData.agentygun_explosionNode or "agentygunexplode"
  agentygun_isInfinite = jbeamData.agentygun_isInfinite or false
  agentygun_forcefieldMode = jbeamData.agentygun_forcefieldMode or false
  
  --reset electrics values for firing all bullets
  for i=1, agentygun_ammo, 1 do
    electrics.values["shootbullet_" .. i] = 0
  end
  
  --reset electrics values for belt control
  for i=1, (agentygun_ammo / agentygun_bulletsPerBeltSection + 1), 1 do
    electrics.values["agentygun_belt_" .. i] = 1
  end
  
  --reset other electrics
  electrics.values['agentygun_fire'] = 0
  electrics.values['agentygun_reload'] = 0
  electrics.values['agentygun_lifter'] = 0
  electrics.values['agentygun_lifter_input'] = 0
  electrics.values.shootnum = 0
  
  --reset local variables
  agentygun_currentbullet_num = 1
  agentygun_timeBetweenBullets = 0
  agentygun_canShoot = true
  agentygun_isBroken = false
  agentygun_currentBeltSection_num = 1
  agentygun_requiredBeltSectionLength = 1
  agentygun_isBeltDetached = false
  reloading = 0
  agentygun_magnum = 0
  agentygun_timeBetweenReload = 0
  agentygun_currentbullet_num = 1
  agentygun_rpgboom = false
  agentygun_rpgreset = 0
  agentygun_bulletsfired = 0
  agentygun_rpghit = 0
  for k, node in pairs (v.data.nodes) do
    if node.name == "agentygun1" then agentygun_originalLocation = k 
    end
    if node.agentygun_bulletID then
      node.teleportthatnode = 0
    end
  end

  
  --assign nodes to variables based on IDs from jbeamData
  for k, node in pairs (v.data.nodes) do
    if node.name == agentygun_gunSoundNodeID then agentygun_gunSoundNode = k  end
	if node.name == agentygun_fireParticleNodeInnerID then agentygun_fireParticleNodeInner = k  end
	if node.name == agentygun_fireParticleNodeOuterID then agentygun_fireParticleNodeOuter = k  end
	if node.name == agentygun_gunSoundNodeID2 then agentygun_gunSoundNode2 = k  end
  if node.name == agentygun_explosionNodeID then agentygun_explosionNode = k  end
	if node.name == agentygun_fireParticleNodeInnerID2 then agentygun_fireParticleNodeInner2 = k  end
	if node.name == agentygun_fireParticleNodeOuterID2 then agentygun_fireParticleNodeOuter2 = k  end
	--we need the cid here since we will be changing properties of the node itself
	if node.name == agentygun_ammoWeightStorageNodeID then agentygun_ammoWeightStorageNode = node.cid end
  if node.name == fire001ID then fire001 = node.cid end
  end
  
  --get break beam cids
  for _,b in pairs(v.data.beams) do
	if b.name == agentygun_breakBeamName then agentygun_breakBeam = b.cid end
	if b.name == agentygun_beltDetachBeamName then agentygun_beltDetachBeam = b.cid end
  end
  
  --display GUI message based on gun type (this doesn't work sometimes for some reason)
  if agentygun_guntype == "flamethrower" then
    guihooks.message("Flamethrower fuel left: 100%", 5, "AgentY_gun")
  elseif agentygun_guntype == "machinegun" then
    if agentygun_hasSecondaryGun then
	  guihooks.message("Bullets left: " .. agentygun_ammo*2, 5, "AgentY_gun")
	else
	  guihooks.message("Bullets left: " .. agentygun_ammo, 5, "AgentY_gun")
	end
  end
  if reloading == 1 then
    guihooks.message("Reloading", 5, "AgentY_gun")
  end
  for k, node in pairs (v.data.nodes) do
    --reset particle properties
    node.horizontalVelocity = nil
    node.newHorizontalVelocity = nil
    node.exploded = false
  end
end


local function updateGFX(dt) -- ms

    electrics.values["shootbullet_" .. agentygun_currentbullet_num - 1] = 0 -- RESET THRUSTERS FOR CARLS EPIC SYSTEM THING
--INFINITE AMMO 
--INFINITE AMMO 
--INFINITE AMMO 
--INFINITE AMMO 
  if agentygun_isInfinite == true then
    if not agentygun_rpg then
      if agentygun_currentbullet_num > 100 then
        agentygun_currentbullet_num = 1
      end
    end
    for k, node in pairs (v.data.nodes) do
      if node.agentygun_bulletID == agentygun_currentbullet_num then
      obj:setNodeMass(node.cid, 0.01)
      end
    end
  end

  --FIRST WE MANAGE THE GUN LIFTING MECHANISM--
  electrics.values['agentygun_lifter'] = math.min(0.8, math.max(-0.8, (electrics.values['agentygun_lifter'] + electrics.values['agentygun_lifter_input'] * dt)))

  -- CHECKING IF GUN IS BROKEN --  
  if agentygun_breakable then
    if agentygun_isBroken then return end --if it's already broken, you can't do anything 
    local agentygun_checkIfBroke = obj:beamIsBroken(agentygun_breakBeam) --check if it just broke each frame
    if agentygun_checkIfBroke then
      guihooks.message(agentygun_guntype .. " broken", 10, "vehicle.damage") --notify the user ONLY ONCE that it just broke
	  agentygun_isBroken =  true -- disable gun
      return
    end
  end
  
  -- CHECKING IF BELT IS DETACHED --  


  if agentygun_beltDetachable then
	local agentygun_checkIfBeltDetached = obj:beamIsBroken(agentygun_beltDetachBeam) --check if it just broke each frame
	if agentygun_checkIfBeltDetached then
		guihooks.message("Ammo belt detached, no bullets!", 10, "vehicle.damage") --notify the user ONLY ONCE that it just broke
		agentygun_isBeltDetached =  true -- will act like it's trying to shoot but has no ammo
	end
  end
  
  -- HIT PARTICLES (HELP WITH CODE BY AWESOMECARL) --
if not agentygun_rpg then
    --track horizontal velocity for each fired node
    for k, node in pairs (v.data.nodes) do
      --check if node is a bullet and then if it has been fired already
      if node.agentygun_bulletID and node.agentygun_bulletID <= agentygun_currentbullet_num - 1 then
        local velocity = vec3(obj:getNodeVelocityVector(node.cid))
        --check if node has just been fired (has no set velocity)
        if node.newHorizontalVelocity == nil then
          node.newHorizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
        else
          --update velocity, store old one in different variable
          node.horizontalVelocity = node.newHorizontalVelocity
          node.newHorizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
          if node.exploded == false then
          --check if node hit something - velocity has decreased significantly
          if agentygun_forcefieldMode then
            if node.horizontalVelocity < 1 and node.horizontalVelocity > 0.01 then
              --electrics.values["shootbullet_" .. node.agentygun_bulletID] = -10 --Permanent force field
            else
              --electrics.values["shootbullet_" .. agentygun_currentbullet_num - 1] = 0
            end
          end
          if node.horizontalVelocity - node.newHorizontalVelocity > 0.01 then
              --add particles once
              obj:addParticleByNodesRelative(node.cid, node.cid, 12, 1, 0.02, 2)
              obj:addParticleByNodesRelative(node.cid, node.cid, 15, 61, 0.02, 2)
              obj:addParticleByNodesRelative(node.cid, node.cid, 10, 62, 0.02, 2)
              obj:addParticleByNodesRelative(node.cid, node.cid, 20, 63, 0.02, 2)
              obj:addParticleByNodesRelative(node.cid, node.cid, 8, 64, 0.02, 2)
              obj:addParticleByNodesRelative(node.cid, node.cid, 12, 65, 0.02, 2)
              obj:addParticleByNodesRelative(node.cid, node.cid, 10, 6, 0.02, 2)
              obj:setNodeMass(node.cid, 0.01)
              --obj:setNodePosition(node.cid, vec3(obj:getNodePosition(agentygun_originalLocation)))
              node.exploded = true
              if agentygun_forcefieldMode then
                electrics.values["shootbullet_" .. node.agentygun_bulletID] = -1000 --EXTREME FORCE FIELD
              end
          else
            node.exploded = false
            end
          end
        end
      end
    end
  end

    --for k, node in pairs (v.data.nodes) do
      --check if node is a bullet and then if it has been fired already
      --if node.agentygun_bulletID and node.agentygun_bulletID <= agentygun_currentbullet_num - 1 then
      --  local velocity = vec3(obj:getNodeVelocityVector(node.cid))
      --  --check if node has just been fired (has no set velocity)
      --  if node.newHorizontalVelocity == nil then
      --    node.newHorizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
      --  else
      --    --update velocity, store old one in different variable
      --    node.horizontalVelocity = node.newHorizontalVelocity
      --    node.newHorizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
      --    --check if node hit something - velocity has decreased significantly
      --    if node.horizontalVelocity - node.newHorizontalVelocity > 0.1 then
      --        obj:setNodePosition(node.cid, vec3(obj:getNodePosition(agentygun_originalLocation)))
      --      end
      --    end
      --  end
      --end
    

    --rpg
    if agentygun_rpg then
    for k, node in pairs (v.data.nodes) do
      --check if node is a bullet and then if it has been fired already
      if node.agentygun_bulletID and node.agentygun_bulletID == agentygun_currentbullet_num - 10 then
        local velocity = vec3(obj:getNodeVelocityVector(node.cid))
        --check if node has just been fired (has no set velocity)
        if node.horizontalVelocity == nil then
          node.horizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
        end
        if node.newHorizontalVelocity == nil then
          node.newHorizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
        else
          --print("step1")
          --update velocity, store old one in different variable
          node.newHorizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
          if node.exploded == false then
            --print("step2")
          obj:addParticleByNodesRelative(node.cid, node.cid, 12, 25, 0, 1) -- add middair particle
          if node.horizontalVelocity - node.newHorizontalVelocity > 0.0001 and agentygun_timeBetweenBullets > 0.001 then  --check if node hit something - velocity has decreased significantly
              --add particles once
              obj:setNodePosition(agentygun_explosionNode, vec3(obj:getNodePosition(node.cid)))
              --explosionlocation = vec3(obj:getNodePosition(node.cid))
              --print("real location:")
              --print(explosionlocation)
              agentygun_rpgboom = true
              agentygun_rpghit = true
              obj:addParticleByNodesRelative(agentygun_explosionNode, agentygun_explosionNode, 12, 29, 0.4, 10)
              obj:addParticleByNodesRelative(agentygun_explosionNode, agentygun_explosionNode, 12, 9, 0.01, 6)
              obj:addParticleByNodesRelative(agentygun_explosionNode, agentygun_explosionNode, 12, 52, 0.01, 4)
              --obj:setNodeMass(node.cid, 0.01)
              node.exploded = true
              --agentygun_rpgreset = agentygun_rpgreset + 1
            else
              node.exploded = false
              --print("resetting exploded")
            end
            node.horizontalVelocity = node.newHorizontalVelocity
          end
        end
      end

      if node.agentygun_bulletID and node.agentygun_bulletID >= agentygun_currentbullet_num - 9 and node.agentygun_bulletID < agentygun_currentbullet_num then
        local velocity = vec3(obj:getNodeVelocityVector(node.cid))
        --check if node has just been fired (has no set velocity)
        if node.horizontalVelocity == nil then
          node.horizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
        end
        if node.newHorizontalVelocity == nil then
          node.newHorizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
        else
          --print("step1")
          --update velocity, store old one in different variable
          node.newHorizontalVelocity = (math.abs(velocity.x) + math.abs(velocity.y))
          if agentygun_rpghit then
          if node.exploded == false then
            --print("step2")
            if node.exploded2 ~= true then
            if node.horizontalVelocity > 1 then

            obj:addParticleByNodesRelative(node.cid, node.cid, 12, 25, 0, 1) -- add middair particle
            end
            end
          if node.horizontalVelocity - node.newHorizontalVelocity > 0.1 then  --check if node hit something - velocity has decreased significantly
            --print("step3")
              --add particles once
              obj:addParticleByNodesRelative(node.cid, node.cid, 1, 29, 0.1, 1)
              obj:addParticleByNodesRelative(node.cid, node.cid, 12, 9, 0.01, 6)
              node.exploded2 = true
              --obj:setNodeMass(node.cid, 0.01)
              --obj:addParticleByNodesRelative(node.cid, node.cid, 12, 52, 0.01, 4)
              --print(node.cid)
            end
            node.horizontalVelocity = node.newHorizontalVelocity
          end
        end
        end
      end
      if node.horizontalVelocity and node.horizontalVelocity < 0.001 then
        if not node.exploded then
          obj:setNodeMass(node.cid, 0.01)
        end
      end
    end
  end
    for k, node in pairs (v.data.nodes) do
      if node.agentygun_bulletID and node.agentygun_bulletID == agentygun_currentbullet_num - 10 then
        --print(node.name)
        --print(vec3(obj:getNodePosition(node.cid)))
      end
      if node.agentygun_bulletID and node.agentygun_bulletID >= agentygun_currentbullet_num - 9 and node.agentygun_bulletID < agentygun_currentbullet_num then
        --print(node.agentygun_bulletID)
        if agentygun_rpgboom then
          if node.exploded == false then
            for _,b in pairs(v.data.beams) do
              if b.agentygun_bulletID and b.agentygun_bulletID >= agentygun_currentbullet_num -9 and b.agentygun_bulletID <= agentygun_currentbullet_num -1 then
                obj:breakBeam(b.cid)
              end
            end
          obj:setNodeMass(node.cid, 70)
          obj:setNodePosition(node.cid, explosionlocation)
          local randX = math.random(-70 + agentygun_bulletvel.x*5, 70 + agentygun_bulletvel.x*5) --made with help from chatgpt
          local randY = math.random(-70 + agentygun_bulletvel.y*5, 70 + agentygun_bulletvel.y*5)
          local randZ = math.random(-40, 60 + agentygun_bulletvel.z)
          local forceVec = vec3(randX, randY, randZ)
          obj:applyForceVector(node.cid, forceVec) -- explosion
          --print(explosionlocation)
          --electrics.values["rpgexplode_" .. agentygun_currentbullet_num -9] = -1
          node.exploded = true
          --agentygun_rpgreset = agentygun_rpgreset + 1
          end
        end
      end
    end
    --print(agentygun_currentbullet_num)
    if agentygun_currentbullet_num > 100 then
      if agentygun_rpgboom then
      --if agentygun_rpgreset >= 100 then
        agentygun_currentbullet_num = 1
        --agentygun_rpgreset = 0
      --end
      end
    end

    agentygun_rpgboom = false
  for k, node in pairs (v.data.nodes) do
    if node.agentygun_bulletID and node.agentygun_bulletID >= agentygun_currentbullet_num - 9 and node.agentygun_bulletID < agentygun_currentbullet_num then
      node.exploded = false
    end
  end

  for k, node in pairs (v.data.nodes) do
    if node.agentygun_bulletID and node.agentygun_bulletID == agentygun_currentbullet_num - 10 then
      explosionlocation = vec3(obj:getNodePosition(node.cid)) --set explosionlocation after
      agentygun_bulletvel = vec3(obj:getNodeVelocityVector(node.cid))
      --print(agentygun_bulletvel)
    end

  end
  -- Reload Button
  -- Reload Button
    -- Reload Button
      -- Reload Button
        -- Reload Button
          -- Reload Button
            -- Reload Button
              -- Reload Button
                -- Reload Button
                  -- Reload Button
                    -- Reload Button
                      -- Reload Button
                        -- Reload Button
  if electrics.values.agentygun_reload == 1 then --axis/button is not being pressed down far enough, ignore this event

    if reloading == 0 then
     electrics.values['agentygun_reload'] = 0   
   if agentygun_magnum > 0 then

    electrics.values['agentygun_reload'] = 0   
    agentygun_magnum = agentygun_magsize + 1
    agentygun_timeBetweenReload = 0
    

   end
  end
  end





  -- CHECKING IF WE CAN SHOOT --
  if agentygun_magnum > agentygun_magsize then
    reloading = 1
    agentygun_timeBetweenReload = agentygun_timeBetweenReload + dt --measure time between firing each bullet
    --guihooks.message("Relod: " .. agentygun_timeBetweenReload, 5, "AgentY_gun")
    if agentygun_timeBetweenReload > agentygun_reloadtime then
    agentygun_magnum = 0
    reloading = 0
    agentygun_timeBetweenReload = 0

    guihooks.message("Reloaded", 1, "AgentY_gun")
    electrics.values.agentygun_lifter = 0
    electrics.values['agentygun_reload'] = 0
    
    end
    end --set reloading

    if agentygun_magnum > agentygun_magsize then 
      if agentygun_timeBetweenReload > 0.25 then
    if agentygun_timeBetweenReload < 0.27 then
    obj:playSFXOnce("CrashTestSound", agentygun_gunSoundNode, 0.4, 6)
    else
    if agentygun_timeBetweenReload > 0.54 then
      if agentygun_timeBetweenReload < 0.58 then

      obj:playSFXOnce("CrashTestSound", agentygun_gunSoundNode, 0.4, 6.6)
      else
        if agentygun_timeBetweenReload > agentygun_reloadtime - 0.02 then
          if agentygun_timeBetweenReload < agentygun_reloadtime then
            obj:playSFXOnce("CrashTestSound", agentygun_gunSoundNode, 0.4, 6)
      end
      end
    end
  end
end
end
end


  agentygun_timeBetweenBullets = agentygun_timeBetweenBullets + dt --measure time between firing each bullet

  if not agentygun_rpg then
  if agentygun_timeBetweenBullets < agentygun_shoot_delay then return end --can't shoot if timer is not over
  end

  if reloading == 1 then 
    guihooks.message("Reloading", 5, "AgentY_gun")
    --guihooks.message("Relod: " .. agentygun_timeBetweenReload, 5, "AgentY_gun")
    electrics.values['agentygun_reload'] = 0
    if agentygun_timeBetweenReload > 0.1 then
    electrics.values.agentygun_lifter = -0.8
    end
    return end


  -- DETECTING INPUT --
  if electrics.values.agentygun_fire < 0.9 then return end --axis/button is not being pressed down far enough, ignore this event
  if agentygun_currentbullet_num > agentygun_ammo then return end -- don't shoot if we are out of ammo
  -- FIRING THE BULLETS --
    	--increase weight of each bullet on the fly
	--this is not very realistic but it's the only way we can deal damage basically
	--it increases bullet energy and keeps momentum because it slows down bullets a bit
	--and if the bullets had this weight from the start, the vehicle wouldn't be able to hold the gun due to the weight
	for k, node in pairs (v.data.nodes) do
    if node.agentygun_bulletID == agentygun_currentbullet_num then
    obj:setNodeMass(node.cid, agentygun_bulletMass)
    end 
  end	
  -- shoot bullet nr. agentygun_currentbullet_num, but only if the ammo belt is attached
  if agentygun_simplifiedMode then --less nodes, no thrusters, works on beam breaking, hopefully less lag
    if not agentygun_isBeltDetached then
	  for _,b in pairs(v.data.beams) do
	    if b.agentygun_bulletID == agentygun_currentbullet_num then 
		  obj:breakBeam(b.cid)
		  end
	  end
	end
  else
  if agentygun_isInfinite then --AwesomeCarl's epic INFINITE AMMO SUPER 6000 ULTRA EFFICIENCY AMMUNITION PROPULSION SYSTEM
    for _,b in pairs(v.data.beams) do
	    if b.agentygun_bulletID == agentygun_currentbullet_num then
		  obj:breakBeam(b.cid)
		  end
	  end
    for k, node in pairs (v.data.nodes) do
      if node.agentygun_bulletID == agentygun_currentbullet_num then
        obj:setNodePosition(node.cid, vec3(obj:getNodePosition(agentygun_originalLocation)))
        --obj:applyForceVector(node.cid, vec3(obj:getNodeVelocityVector(agentygun_fireParticleNodeInner)))
        electrics.values["shootbullet_" .. agentygun_currentbullet_num] = -1
        
        node.exploded = false
	    end
      if node.agentygun_bulletID and node.agentygun_bulletID >= agentygun_currentbullet_num - 9 and node.agentygun_bulletID < agentygun_currentbullet_num then
        node.exploded2 = false
      end
	    end
  else
	if not agentygun_isBeltDetached then electrics.values["shootbullet_" .. agentygun_currentbullet_num] = 1 end
  end
  end
  if not agentygun_rpg then
  agentygun_currentbullet_num = agentygun_currentbullet_num + 1 --go to next bullet in line
  else
    agentygun_currentbullet_num = agentygun_currentbullet_num + 10 --go to next bullet in line
    agentygun_magnum = agentygun_magnum + 9
    agentygun_bulletsfired = agentygun_bulletsfired + 9
  end
  agentygun_rpghit = false
  agentygun_canShoot = false --disable shooting until time passes
  agentygun_timeBetweenBullets = 0 --reset timer
  agentygun_bulletsLeft = agentygun_ammo - agentygun_currentbullet_num + 1
  electrics.values.shootnum = agentygun_bulletsLeft

  agentygun_magnum = agentygun_magnum + 1
  agentygun_bulletsfired = agentygun_bulletsfired + 1
  guihooks.message("Bullets fired: " .. agentygun_bulletsfired, 1, "AgentYgunbullets")

  --Remove the weight of each node from the ammo storage weight
  if agentygun_decreaseAmmoWeightOnShooting == true then 
	local currentAmmoNodeMass = obj:getNodeMass(agentygun_ammoWeightStorageNode)
	local AmmoNodeMassAfterShooting = currentAmmoNodeMass - agentygun_bulletMassInAmmo
	obj:setNodeMass(agentygun_ammoWeightStorageNode, AmmoNodeMassAfterShooting)


end
  
  --Now we have different behavior for different gun types
  
  if agentygun_guntype == "Flamethrower" then
    agentygun_bulletsLeftPercentage = agentygun_bulletsLeft / agentygun_ammo * 100 --display ammo as percentage of fuel left
    guihooks.message("Flamethrower fuel left: " .. agentygun_bulletsLeftPercentage .. "%", 5, "AgentY_gun") 
    --play fire sound
    obj:playSFXOnce("event:>Vehicle>Fire>Fire_Ignition", agentygun_gunSoundNode, 1, 1)	 
  
  elseif (agentygun_guntype == "Machinegun") and (agentygun_isBeltDetached == false) then
  
    if agentygun_hasSecondaryGun then
  
		guihooks.message("Bullets left: " .. agentygun_bulletsLeft*2, 5, "AgentY_gun")
		--play fire sound
		obj:playSFXOnce("CrashTestSound", agentygun_gunSoundNode, 1, 2)
		obj:playSFXOnce("CrashTestSound", agentygun_gunSoundNode2, 1, 2)
		--show firing particles
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 15, 61, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 10, 62, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 20, 63, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 8, 64, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 12, 65, 0, 1)
		--2
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner2, agentygun_fireParticleNodeOuter2, 15, 61, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner2, agentygun_fireParticleNodeOuter2, 10, 62, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner2, agentygun_fireParticleNodeOuter2, 20, 63, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner2, agentygun_fireParticleNodeOuter2, 8, 64, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner2, agentygun_fireParticleNodeOuter2, 12, 65, 0, 1)
		--show smoke
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 10, 6, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner2, agentygun_fireParticleNodeOuter2, 10, 6, 0, 1)
  
    else
  
		--play fire sound
    if agentygun_rpg then
      obj:playSFXOnce("CrashTestSound", agentygun_gunSoundNode, 1.5, 1.2)
    else
      obj:playSFXOnce("CrashTestSound", agentygun_gunSoundNode, 1, 2)
    end
		--show firing particles
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 15, 61, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 10, 62, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 20, 63, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 8, 64, 0, 1)
		obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 12, 65, 0, 1)

		--show smoke
    if agentygun_shoot_delay < 0.07 then
      obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 10, 6, 0.5, 1)
    else
      obj:addParticleByNodesRelative(agentygun_fireParticleNodeInner, agentygun_fireParticleNodeOuter, 10, 6, 0, 1)
    end
	
	end





	
	-- BELT ANIMATION --
	if (agentygun_hasBelt == true) and (agentygun_isBeltDetached == false) then
		--determine which section of the belt we are currently retracing based on the current bullet number
		agentygun_currentBeltSection_num = math.floor((agentygun_currentbullet_num - 2) / agentygun_bulletsPerBeltSection) + 1 --not sure why this works but it does lol 
		--retrace current section by a set amount
		agentygun_requiredBeltSectionLength = agentygun_requiredBeltSectionLength - (1 / agentygun_bulletsPerBeltSection)
		if agentygun_requiredBeltSectionLength < 0 then agentygun_requiredBeltSectionLength = agentygun_requiredBeltSectionLength + 1 end
		electrics.values["agentygun_belt_" .. agentygun_currentBeltSection_num] = agentygun_requiredBeltSectionLength - 1
	end
	
  end





end

local function liftGun(value)
  electrics.values.agentygun_lifter_input = value
end






-- public interface

M.init         = init
M.updateGFX    = updateGFX
M.liftGun      = liftGun

return M
