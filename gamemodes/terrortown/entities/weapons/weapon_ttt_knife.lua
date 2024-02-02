AddCSLuaFile()

SWEP.HoldType               = "knife"

local backstab_knife_desc = [[
Kills targets instantly and
silently upon backstab, but only has a single use.

Can be thrown using alternate fire.]]

-- EyeAngles() is broken on the client, I will fix this when Facepunch do
-- So we send a single bit every tick to tell them if they have a kill
-- Only send when they have the knife out
-- We only send a single bool because we are sending this every TICK!
if SERVER then
   util.AddNetworkString("is_backstab_kill")
end

if CLIENT then
   SWEP.PrintName           = "Backstab Knife"
   SWEP.Slot                = 6

   SWEP.ViewModelFlip       = false
   SWEP.ViewModelFOV        = 54
   SWEP.DrawCrosshair       = false

   SWEP.EquipMenuData = {
      type = "item_weapon",
      desc = backstab_knife_desc
   };

   SWEP.Icon                = "vgui/ttt/icon_knife"
   SWEP.IconLetter          = "j"

   net.Receive("is_backstab_kill", function()
      IS_BACKSTAB = net.ReadBool()
   end)
end

SWEP.Base                   = "weapon_tttbase"

SWEP.UseHands               = true
SWEP.ViewModel              = "models/weapons/cstrike/c_knife_t.mdl"
SWEP.WorldModel             = "models/weapons/w_knife_t.mdl"

SWEP.Primary.Damage         = 20
SWEP.Primary.ClipSize       = -1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic      = true
SWEP.Primary.Delay          = 1.1
SWEP.Primary.Ammo           = "none"

SWEP.Secondary.ClipSize     = -1
SWEP.Secondary.DefaultClip  = -1
SWEP.Secondary.Automatic    = true
SWEP.Secondary.Ammo         = "none"
SWEP.Secondary.Delay        = 1.4

SWEP.Kind                   = WEAPON_EQUIP
SWEP.CanBuy                 = {ROLE_TRAITOR} -- only traitors can buy
SWEP.LimitedStock           = true -- only buyable once
SWEP.WeaponID               = AMMO_KNIFE

SWEP.IsSilent               = true

-- Pull out faster than standard guns
SWEP.DeploySpeed            = 2

IS_BACKSTAB             = false

BACKSTAB_ANGLE         = 90

function isBackstabKill(victim, attacker)
   local targetAngle = victim:GetAngles().y
   local attackerAngle = attacker:GetAngles().y

   local angleDiff = math.abs(targetAngle - attackerAngle)
   angleDiff = angleDiff % 360 -- Normalize the angle difference

   -- Check if the attacker is behind the target within the backstab angle
   if angleDiff <= BACKSTAB_ANGLE / 2 or angleDiff >= 360 - BACKSTAB_ANGLE / 2 then
       return true
   else
       return false
   end
end

function SWEP:Think()
   if SERVER then
      local player = self:GetOwner()
      --Check if player is looking at another player
      local tr = self:GetOwner():GetEyeTrace(MASK_SHOT)
      net.Start("is_backstab_kill")
      if tr.HitNonWorld and IsValid(tr.Entity) and tr.Entity:IsPlayer() and isBackstabKill(tr.Entity, player) then
         net.WriteBool(true)
      else net.WriteBool(false)
      end
      net.Send(player)
   end
end

function SWEP:PrimaryAttack()
   self.Weapon:SetNextPrimaryFire( CurTime() + self.Primary.Delay )
   self.Weapon:SetNextSecondaryFire( CurTime() + self.Secondary.Delay )

   if not IsValid(self:GetOwner()) then return end

   self:GetOwner():LagCompensation(true)

   local spos = self:GetOwner():GetShootPos()
   local sdest = spos + (self:GetOwner():GetAimVector() * 70)

   local kmins = Vector(1,1,1) * -10
   local kmaxs = Vector(1,1,1) * 10

   local tr = util.TraceHull({start=spos, endpos=sdest, filter=self:GetOwner(), mask=MASK_SHOT_HULL, mins=kmins, maxs=kmaxs})

   -- Hull might hit environment stuff that line does not hit
   if not IsValid(tr.Entity) then
      tr = util.TraceLine({start=spos, endpos=sdest, filter=self:GetOwner(), mask=MASK_SHOT_HULL})
   end

   local hitEnt = tr.Entity

   -- effects
   if IsValid(hitEnt) then
      self.Weapon:SendWeaponAnim( ACT_VM_HITCENTER )

      local edata = EffectData()
      edata:SetStart(spos)
      edata:SetOrigin(tr.HitPos)
      edata:SetNormal(tr.Normal)
      edata:SetEntity(hitEnt)

      if hitEnt:IsPlayer() or hitEnt:GetClass() == "prop_ragdoll" then
         util.Effect("BloodImpact", edata)
      end
   else
      self.Weapon:SendWeaponAnim( ACT_VM_MISSCENTER )
   end

   if SERVER then
      self:GetOwner():SetAnimation( PLAYER_ATTACK1 )
   end


   if SERVER and tr.Hit and tr.HitNonWorld and IsValid(hitEnt) then
      if hitEnt:IsPlayer() then
         -- knife damage is never karma'd, so don't need to take that into
         -- account we do want to avoid rounding error strangeness caused by
         -- other damage scaling, causing a death when we don't expect one, so
         -- when the target's health is close to kill-point we just kill
         if isBackstabKill(tr.Entity, self:GetOwner()) then
            self:StabKill(tr, spos, sdest)
         else
            local dmg = DamageInfo()
            dmg:SetDamage(self.Primary.Damage)
            dmg:SetAttacker(self:GetOwner())
            dmg:SetInflictor(self.Weapon or self)
            dmg:SetDamageForce(self:GetOwner():GetAimVector() * 5)
            dmg:SetDamagePosition(self:GetOwner():GetPos())
            dmg:SetDamageType(DMG_SLASH)

            hitEnt:DispatchTraceAttack(dmg, spos + (self:GetOwner():GetAimVector() * 3), sdest)
         end
      end
   end

   self:GetOwner():LagCompensation(false)
end

function SWEP:StabKill(tr, spos, sdest)
   local target = tr.Entity

   local dmg = DamageInfo()
   dmg:SetDamage(2000)
   dmg:SetAttacker(self:GetOwner())
   dmg:SetInflictor(self.Weapon or self)
   dmg:SetDamageForce(self:GetOwner():GetAimVector())
   dmg:SetDamagePosition(self:GetOwner():GetPos())
   dmg:SetDamageType(DMG_SLASH)

   -- now that we use a hull trace, our hitpos is guaranteed to be
   -- terrible, so try to make something of it with a separate trace and
   -- hope our effect_fn trace has more luck

   -- first a straight up line trace to see if we aimed nicely
   local retr = util.TraceLine({start=spos, endpos=sdest, filter=self:GetOwner(), mask=MASK_SHOT_HULL})

   -- if that fails, just trace to worldcenter so we have SOMETHING
   if retr.Entity != target then
      local center = target:LocalToWorld(target:OBBCenter())
      retr = util.TraceLine({start=spos, endpos=center, filter=self:GetOwner(), mask=MASK_SHOT_HULL})
   end


   -- create knife effect creation fn
   local bone = retr.PhysicsBone
   local pos = retr.HitPos
   local norm = tr.Normal
   local ang = Angle(-28,0,0) + norm:Angle()
   ang:RotateAroundAxis(ang:Right(), -90)
   pos = pos - (ang:Forward() * 7)

   local prints = self.fingerprints
   local ignore = self:GetOwner()

   target.effect_fn = function(rag)
                         -- we might find a better location
                         local rtr = util.TraceLine({start=pos, endpos=pos + norm * 40, filter=ignore, mask=MASK_SHOT_HULL})

                         if IsValid(rtr.Entity) and rtr.Entity == rag then
                            bone = rtr.PhysicsBone
                            pos = rtr.HitPos
                            ang = Angle(-28,0,0) + rtr.Normal:Angle()
                            ang:RotateAroundAxis(ang:Right(), -90)
                            pos = pos - (ang:Forward() * 10)

                         end

                         local knife = ents.Create("prop_physics")
                         knife:SetModel("models/weapons/w_knife_t.mdl")
                         knife:SetPos(pos)
                         knife:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
                         knife:SetAngles(ang)
                         knife.CanPickup = false

                         knife:Spawn()

                         local phys = knife:GetPhysicsObject()
                         if IsValid(phys) then
                            phys:EnableCollisions(false)
                         end

                         constraint.Weld(rag, knife, bone, 0, 0, true)

                         -- need to close over knife in order to keep a valid ref to it
                         rag:CallOnRemove("ttt_knife_cleanup", function() SafeRemoveEntity(knife) end)
                      end


   -- seems the spos and sdest are purely for effects/forces?
   target:DispatchTraceAttack(dmg, spos + (self:GetOwner():GetAimVector() * 3), sdest)

   -- target appears to die right there, so we could theoretically get to
   -- the ragdoll in here...

   self:Remove()
end

function SWEP:SecondaryAttack()
   self.Weapon:SetNextPrimaryFire( CurTime() + self.Primary.Delay )
   self.Weapon:SetNextSecondaryFire( CurTime() + self.Secondary.Delay )


   self.Weapon:SendWeaponAnim( ACT_VM_MISSCENTER )

   if SERVER then
      local ply = self:GetOwner()
      if not IsValid(ply) then return end

      ply:SetAnimation( PLAYER_ATTACK1 )

      local ang = ply:EyeAngles()

      if ang.p < 90 then
         ang.p = -10 + ang.p * ((90 + 10) / 90)
      else
         ang.p = 360 - ang.p
         ang.p = -10 + ang.p * -((90 + 10) / 90)
      end

      local vel = math.Clamp((90 - ang.p) * 5.5, 550, 800)

      local vfw = ang:Forward()
      local vrt = ang:Right()

      local src = ply:GetPos() + (ply:Crouching() and ply:GetViewOffsetDucked() or ply:GetViewOffset())

      src = src + (vfw * 1) + (vrt * 3)

      local thr = vfw * vel + ply:GetVelocity()

      local knife_ang = Angle(-28,0,0) + ang
      knife_ang:RotateAroundAxis(knife_ang:Right(), -90)

      local knife = ents.Create("ttt_knife_proj")
      if not IsValid(knife) then return end
      knife:SetPos(src)
      knife:SetAngles(knife_ang)

      knife:Spawn()

      knife.Damage = self.Primary.Damage

      knife:SetOwner(ply)

      local phys = knife:GetPhysicsObject()
      if IsValid(phys) then
         phys:SetVelocity(thr)
         phys:AddAngleVelocity(Vector(0, 1500, 0))
         phys:Wake()
      end

      self:Remove()
   end
end

function SWEP:Equip()
   self.Weapon:SetNextPrimaryFire( CurTime() + (self.Primary.Delay * 1.5) )
   self.Weapon:SetNextSecondaryFire( CurTime() + (self.Secondary.Delay * 1.5) )
end

function SWEP:PreDrop()
   -- for consistency, dropped knife should not have DNA/prints
   self.fingerprints = {}
end

function SWEP:OnRemove()
   if CLIENT and IsValid(self:GetOwner()) and self:GetOwner() == LocalPlayer() and self:GetOwner():Alive() then
      RunConsoleCommand("lastinv")
   end
end

if CLIENT then
   local T = LANG.GetTranslation

   function SWEP:DrawHUD()
      if IS_BACKSTAB then
         local x = ScrW() / 2.0
         local y = ScrH() / 2.0

         surface.SetDrawColor(255, 0, 0, 255)

         local outer = 20
         local inner = 10
         surface.DrawLine(x - outer, y - outer, x - inner, y - inner)
         surface.DrawLine(x + outer, y + outer, x + inner, y + inner)

         surface.DrawLine(x - outer, y + outer, x - inner, y + inner)
         surface.DrawLine(x + outer, y - outer, x + inner, y - inner)

         draw.SimpleText(T("knife_instant"), "TabLarge", x, y - 30, COLOR_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
      end

      return self.BaseClass.DrawHUD(self)
   end
end


