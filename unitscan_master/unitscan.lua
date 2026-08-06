local unitscan = CreateFrame'Frame'
local nearby_targets = {}
local found_rares = {}
local zone_frame = CreateFrame("Frame")
zone_frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zone_frame:SetScript("OnEvent", function()
    found_rares = {}
end)
local rare_spawns = {}
local initialized = false
local looting = false

unitscan:SetScript('OnUpdate', function() unitscan.UPDATE() end)
unitscan:SetScript('OnEvent', function()
	if event == 'VARIABLES_LOADED' then
		unitscan.LOAD()
		initialized = true
		unitscan.refresh_nearby_targets()
	elseif event == 'PLAYER_ENTERING_WORLD' or event == 'ZONE_CHANGED_NEW_AREA' then
		unitscan.refresh_nearby_targets()
	elseif event == 'LOOT_OPENED' then
		looting = true
	elseif event == 'LOOT_CLOSED' then
		looting = false
		-- Laisse passer un cycle avant de reprendre les scans apres le loot.
		unitscan.last_check = GetTime()
	end
end)
unitscan:RegisterEvent'VARIABLES_LOADED'
unitscan:RegisterEvent'PLAYER_ENTERING_WORLD'
unitscan:RegisterEvent'ZONE_CHANGED_NEW_AREA'
unitscan:RegisterEvent'LOOT_OPENED'
unitscan:RegisterEvent'LOOT_CLOSED'

local BROWN = {.7, .15, .05}
local YELLOW = {1, 1, .15}
local CHECK_INTERVAL = .3

-- unitscan_targets = {}

do
	local last_played
	
	function unitscan.play_sound()
		if not last_played or GetTime() - last_played > 10 then -- 8
			SetCVar('MasterSoundEffects', 0)
			SetCVar('MasterSoundEffects', 1)
			PlaySoundFile[[Interface\AddOns\unitscan\Event_wardrum_ogre.ogg]]
			PlaySoundFile[[Interface\AddOns\unitscan\scourge_horn.ogg]]
			last_played = GetTime()
		end
	end
end

function unitscan.alert_target(target_name)
	unitscan.play_sound()
	unitscan.flash.animation:Play()
	unitscan.button:set_target(target_name)
end

function unitscan.refresh_nearby_targets()
	local zone = GetRealZoneText()
	nearby_targets = {}
	if not zone then return end

	for name, rare_zone in pairs(rare_spawns) do
		if zone == rare_zone or strfind(zone, rare_zone, 1, true) then
			tinsert(nearby_targets, name)
		end
	end

	sort(nearby_targets, function(name1, name2) return name1 < name2 end)
end

function unitscan.check_for_targets()
	for name in pairs(unitscan_targets) do
		if unitscan.target(name, unitscan.alert_target) then
			unitscan.toggle_target(name)
			found_rares[name] = true
		end
	end

	-- Le scan automatique repose sur TargetByName(), qui change reellement
	-- la cible sous Vanilla. Ne pas l'utiliser en combat : un changement de
	-- cible, meme restaure aussitot, peut interrompre l'attaque automatique.
	if UnitAffectingCombat('player') then
		return
	end

	for _, name in ipairs(nearby_targets) do
		if not found_rares[name] then
			-- Declenche l'alerte pendant que le rare est encore cible. Cela
			-- permet aussi au modele 3D de recuperer la bonne unite avant que
			-- unitscan.target() restaure la cible precedente.
			if unitscan.target(name, unitscan.alert_target) then
				found_rares[name] = true
			end
		end
	end
end

do
	local pass = function() end

	function unitscan.target(name, on_found)
		local had_target = UnitExists'target'
		local original_target = UnitName'target'
		local orig = UIErrorsFrame_OnEvent
		UIErrorsFrame_OnEvent = pass
		TargetByName(name, true)
		UIErrorsFrame_OnEvent = orig
		local target = UnitName'target'
		local found = target and strupper(target) == name

		-- TargetByName is needed to scan in Vanilla, but must not steal the
		-- player's target.  Build the alert while the rare is selected, then
		-- restore the previous target (or leave no target if there was none).
		if found and on_found then
			on_found(target)
		end
		if had_target and target ~= original_target then
			TargetLastTarget()
		elseif not had_target then
			ClearTarget()
		end

		return found
	end
end

function unitscan.LOAD()
	if not unitscan_targets then
		unitscan_targets = {}
	end
	do
		local flash = CreateFrame'Frame'
		unitscan.flash = flash
		flash:Show()
		flash:SetAllPoints()
		flash:SetAlpha(0)
		flash:SetFrameStrata'FULLSCREEN_DIALOG'
		
		local texture = flash:CreateTexture()
		texture:SetBlendMode'ADD'
		texture:SetAllPoints()
		texture:SetTexture[[Interface\FullScreenTextures\LowHealth]]

		flash.animation = CreateFrame'Frame'
		flash.animation:Hide()
		flash.animation:SetScript('OnUpdate', function()
			local t = GetTime() - this.t0
			if t <= .5 then
				flash:SetAlpha(t * 2)
			elseif t <= 1 then
				flash:SetAlpha(1)
			elseif t <= 1.5 then
				flash:SetAlpha(1 - (t - 1) * 2)
			else
				flash:SetAlpha(0)
				this.loops = this.loops - 1
				if this.loops == 0 then
					this.t0 = nil
					this:Hide()
				else
					this.t0 = GetTime()
				end
			end
		end)
		function flash.animation:Play()
			if self.t0 then
				self.loops = 4
			else
				self.t0 = GetTime()
				self.loops = 3
			end
			self:Show()
		end
	end
	
	local button = CreateFrame('Button', 'unitscan_button', UIParent)
	button:Hide()
	unitscan.button = button
	button:SetPoint('BOTTOM', UIParent, 0, 128)
	button:SetWidth(150)
	button:SetHeight(42)
	button:SetScale(1.25)
	button:SetMovable(true)
	button:SetUserPlaced(true)
	button:SetClampedToScreen(true)
	button:SetScript('OnMouseDown', function()
		if IsControlKeyDown() then
			this:RegisterForClicks()
			this:StartMoving()
		end
	end)
	button:SetScript('OnMouseUp', function()
		this:StopMovingOrSizing()
		this:RegisterForClicks'LeftButtonDown'
	end)
	button:SetFrameStrata'FULLSCREEN_DIALOG'
	button:SetNormalTexture[[Interface\AddOns\unitscan\UI-Achievement-Parchment-Horizontal]]
	button:SetBackdrop{
		tile = true,
		edgeSize = 16,
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	}
	button:SetBackdropBorderColor(unpack(BROWN))
	button:SetScript('OnEnter', function()
		this:SetBackdropBorderColor(unpack(YELLOW))
	end)
	button:SetScript('OnLeave', function()
		this:SetBackdropBorderColor(unpack(BROWN))
	end)
	button:SetScript('OnClick', function()
		TargetByName(this:GetText(), true)
	end)
	function button:set_target(target_name)
		local name = target_name or UnitName'target'
		if not name then return end
		self:SetText(name)

		self.model:reset()
		self.model:SetUnit'target'

		self:Show()
		self.glow.animation:Play()
		self.shine.animation:Play()
	end
	
	do
		local background = button:GetNormalTexture()
		background:SetDrawLayer'BACKGROUND'
		background:ClearAllPoints()
		background:SetPoint('BOTTOMLEFT', 3, 3)
		background:SetPoint('TOPRIGHT', -3, -3)
		background:SetTexCoord(0, 1, 0, .25)
	end
	
	do
		local title_background = button:CreateTexture(nil, 'BORDER')
		title_background:SetTexture[[Interface\AddOns\unitscan\UI-Achievement-Title]]
		title_background:SetPoint('TOPRIGHT', -5, -5)
		title_background:SetPoint('LEFT', 5, 0)
		title_background:SetHeight(18)
		title_background:SetTexCoord(0, .9765625, 0, .3125)
		title_background:SetAlpha(.8)

		local title = button:CreateFontString(nil, 'OVERLAY')
		title:SetFont([[Fonts\FRIZQT__.TTF]], 14)
		title:SetShadowOffset(1, -1)
		title:SetPoint('TOPLEFT', title_background, 0, 0)
		title:SetPoint('RIGHT', title_background)
		button:SetFontString(title)

		local subtitle = button:CreateFontString(nil, 'OVERLAY')
		subtitle:SetFont([[Fonts\FRIZQT__.TTF]], 9)
		subtitle:SetTextColor(0, 0, 0)
		subtitle:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -4)
		subtitle:SetPoint('RIGHT', title )
		subtitle:SetText'Unit Found!'
	end
	
	do
		local model = CreateFrame('PlayerModel', nil, button)
		button.model = model
		model:SetPoint('BOTTOMLEFT', button, 'TOPLEFT', 0, -4)
		model:SetPoint('RIGHT', 0, 0)
		model:SetHeight(button:GetWidth() * .6)
		
		do
			local last_update, delay
			function model:on_update()
				this:SetFacing(this:GetFacing() + (GetTime() - last_update) * math.pi / 4)
				last_update = GetTime()
			end
			
			function model:on_update_model()
				if delay > 0 then
					delay = delay - 1
					return
				end
				
				this:SetScript('OnUpdateModel', nil)
				this:SetScript('OnUpdate', this.on_update)
				this:SetModelScale(.75)
				this:SetAlpha(1)	
				last_update = GetTime()
			end
			
			function model:reset()
				self:SetAlpha(0)
				self:SetFacing(0)
				self:SetModelScale(1)
				self:ClearModel()
				self:SetScript('OnUpdate', nil)
				self:SetScript("OnUpdateModel", self.on_update_model)
				delay = 10 -- to prevent scaling bugs
			end
		end
	end
	
	do
		local close = CreateFrame('Button', nil, button, 'UIPanelCloseButton')
		close:SetPoint('TOPRIGHT', 0, 0)
		close:SetWidth(32)
		close:SetHeight(32)
		close:SetScale(.8)
		close:SetHitRectInsets(8, 8, 8, 8)
	end
	
	do
		local glow = button.model:CreateTexture(nil, 'OVERLAY')
		button.glow = glow
		glow:SetPoint('CENTER', button, 'CENTER')
		glow:SetWidth(400 / 300 * button:GetWidth())
		glow:SetHeight(171 / 70 * button:GetHeight())
		glow:SetTexture[[Interface\AddOns\unitscan\UI-Achievement-Alert-Glow]]
		glow:SetBlendMode'ADD'
		glow:SetTexCoord(0, .78125, 0, .66796875)
		glow:SetAlpha(0)

		glow.animation = CreateFrame'Frame'
		glow.animation:Hide()
		glow.animation:SetScript('OnUpdate', function()
			local t = GetTime() - this.t0
			if t <= .2 then
				glow:SetAlpha(t * 5)
			elseif t <= .7 then
				glow:SetAlpha(1 - (t - .2) * 2)
			else
				glow:SetAlpha(0)
				this:Hide()
			end
		end)
		function glow.animation:Play()
			self.t0 = GetTime()
			self:Show()
		end
	end

	do
		local shine = button:CreateTexture(nil, 'ARTWORK')
		button.shine = shine
		shine:SetPoint('TOPLEFT', button, 0, 8)
		shine:SetWidth(67 / 300 * button:GetWidth())
		shine:SetHeight(1.28 * button:GetHeight())
		shine:SetTexture[[Interface\AddOns\unitscan\UI-Achievement-Alert-Glow]]
		shine:SetBlendMode'ADD'
		shine:SetTexCoord(.78125, .912109375, 0, .28125)
		shine:SetAlpha(0)
		
		shine.animation = CreateFrame'Frame'
		shine.animation:Hide()
		shine.animation:SetScript('OnUpdate', function()
			local t = GetTime() - this.t0
			if t <= .3 then
				shine:SetPoint('TOPLEFT', button, 0, 8)
			elseif t <= .7 then
				shine:SetPoint('TOPLEFT', button, (t - .3) * 2.5 * this.distance, 8)
			end
			if t <= .3 then
				shine:SetAlpha(0)
			elseif t <= .5 then
				shine:SetAlpha(1)
			elseif t <= .7 then
				shine:SetAlpha(1 - (t - .5) * 5)
			else
				shine:SetAlpha(0)
				this:Hide()
			end
		end)
		function shine.animation:Play()
			self.t0 = GetTime()
			self.distance = button:GetWidth() - shine:GetWidth() + 8
			self:Show()
		end
	end
end

do
	unitscan.last_check = GetTime()
	function unitscan.UPDATE()
		if not initialized or looting or (LootFrame and LootFrame:IsShown()) then return end
		if GetTime() - unitscan.last_check >= CHECK_INTERVAL then
			unitscan.last_check = GetTime()
			unitscan.check_for_targets()
		end
	end
end

function unitscan.print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(LIGHTYELLOW_FONT_COLOR_CODE .. '<unitscan> ' .. msg)
	end
end

function unitscan.sorted_targets()
	local sorted_targets = {}
	for key in pairs(unitscan_targets) do
		tinsert(sorted_targets, key)
	end
	sort(sorted_targets, function(key1, key2) return key1 < key2 end)
	return sorted_targets
end

function unitscan.toggle_target(name)
	local key = strupper(name)
	if unitscan_targets[key] then
		unitscan_targets[key] = nil
		unitscan.print('- ' .. key)
	elseif key ~= '' then
		unitscan_targets[key] = true
		unitscan.print('+ ' .. key)
	end
end
	
SLASH_UNITSCAN1 = '/unitscan'
function SlashCmdList.UNITSCAN(parameter)
	local _, _, name = strfind(parameter or '', '^%s*(.-)%s*$')
	
	if name == 'nearby' then
		unitscan.print('Rares scannes dans la zone actuelle :')
		if table.getn(nearby_targets) == 0 then
			unitscan.print('(aucun rare connu dans cette zone)')
		else
			for _, rare_name in ipairs(nearby_targets) do
				unitscan.print(rare_name)
			end
		end
	elseif name == 'help' then
		unitscan.print('/unitscan <nom> : ajoute ou retire une cible manuelle')
		unitscan.print('/unitscan nearby : affiche les rares scannes dans la zone')
		unitscan.print('/unitscan : affiche les cibles manuelles')
	elseif name == '' then
		unitscan.print('Cibles manuelles :')
		for _, key in ipairs(unitscan.sorted_targets()) do
			unitscan.print(key)
		end
	else
		unitscan.toggle_target(name)
	end
end

-- Liste frFR des rares de WoW Vanilla, reprise de la version 2.4.3.
-- Seuls les PNJ des zones disponibles en 1.12 sont inclus.
-- RARE_SPAWNS_FR_BEGIN
rare_spawns = {
	["AZUROUS"] = "Winterspring",
	["GENERAL COLBATANN"] = "Winterspring",
	["KASHOCH THE REAVER"] = "Winterspring",
	["LADY HEDERINE"] = "Winterspring",
	["ALSHIRR BANEBREATH"] = "Felwood",
	["DESSECUS"] = "Felwood",
	["IMMOLATUS"] = "Felwood",
	["MONNOS THE ELDER"] = "Azshara",
	["SCALEBEARD"] = "Azshara",
	["BROTHER RAVENOAK"] = "Stonetalon Mountains",
	["FOREMAN RIGGER"] = "Stonetalon Mountains",
	["SISTER RIVEN"] = "Stonetalon Mountains",
	["SORROW WING"] = "Stonetalon Mountains",
	["TASKMASTER WHIPFANG"] = "Stonetalon Mountains",
	["AEAN SWIFTRIVER"] = "The Barrens",
	["AMBASSADOR BLOODRAGE"] = "The Barrens",
	["BRONTUS"] = "The Barrens",
	["CAPTAIN GEROGG HAMMERTOE"] = "The Barrens",
	["ELDER MYSTIC RAZORSNOUT"] = "The Barrens",
	["GESHARAHAN"] = "The Barrens",
	["HAGG TAURENBANE"] = "The Barrens",
	["HANNAH BLADELEAF"] = "The Barrens",
	["MARCUS BEL"] = "The Barrens",
	["ROCKLANCE"] = "The Barrens",
	["SISTER RATHTALON"] = "The Barrens",
	["SWIFTMANE"] = "The Barrens",
	["SWINEGART SPEARHIDE"] = "The Barrens",
	["TAKK THE LEAPER"] = "The Barrens",
	["THORA FEATHERMOON"] = "The Barrens",
	["CAPTAIN FLAT TUSK"] = "Durotar",
	["FELWEAVER SCORNN"] = "Durotar",
	["BRIMGORE"] = "Dustwallow Marsh",
	["SISTER HATELASH"] = "Mulgore",
	["HEARTRAZOR"] = "Thousand Needles",
	["IRONEYE THE INVINCIBLE"] = "Thousand Needles",
	["VILE STING"] = "Thousand Needles",
	["JIN'ZALLAH THE SANDBRINGER"] = "Tanaris",
	["WARLEADER KRAZZILAK"] = "Tanaris",
	["GRUFF"] = "Un'Goro Crater",
	["KING MOSH"] = "Un'Goro Crater",
	["REX ASHIL"] = "Silithus",
	["SCARLET EXECUTIONER"] = "Western Plaguelands",
	["SCARLET HIGH CLERIST"] = "Western Plaguelands",
	["TAMRA STORMPIKE"] = "Hillsbrad Foothills",
	["NARILLASANZ"] = "Alterac Mountains",
	["GRIMUNGOUS"] = "The Hinterlands",
	["MITH'RETHIS THE ENCHANTER"] = "The Hinterlands",
	["DARBEL MONTROSE"] = "Arathi Highlands",
	["FOULBELLY"] = "Arathi Highlands",
	["RUUL ONESTONE"] = "Arathi Highlands",
	["EMOGG THE CRUSHER"] = "Loch Modan",
	["SIEGE GOLEM"] = "Badlands",
	["HIGHLORD MASTROGONDE"] = "Searing Gorge",
	["HEMATOS"] = "Burning Steppes",
	["LORD CAPTAIN WYRMAK"] = "Swamp of Sorrows",
	["JADE"] = "Swamp of Sorrows",
	["HIGH PRIESTESS HAI'WATNA"] = "Stranglethorn Vale",
	["MOSH'OGG BUTCHER"] = "Stranglethorn Vale",
	["ANATHEMUS"] = "Badlands",
	["ZARICOTL"] = "Badlands",
	["DEVIATE FAERIE DRAGON"] = "Wailing Caverns",
	["MESHLOK THE HARVESTER"] = "Maraudon",
	["BLIND HUNTER"] = "Razorfen Kraul",
	["EARTHCALLER HALMGAR"] = "Razorfen Kraul",
	["RAZORFEN SPEARHIDE"] = "Razorfen Kraul",
	["ZERILLIS"] = "Zul'Farrak",
	["AZSHIR THE SLEEPLESS"] = "Scarlet Monastery",
	["HEARTHSINGER FORRESTEN"] = "Stratholme",
	["SKUL"] = "Stratholme",
	["STONESPINE"] = "Stratholme",
	["DEATHSWORN CAPTAIN"] = "Shadowfang Keep",
	["DARK IRON AMBASSADOR"] = "Gnomeregan",
	["LORD ROCCOR"] = "Blackrock Depths",
	["PANZOR THE INVINCIBLE"] = "Blackrock Depths",
	["PYROMANCER LOREGRAIN"] = "Blackrock Depths",
	["VEREK"] = "Blackrock Depths",
	["WARDER STILGISS"] = "Blackrock Depths",
	["BANNOK GRIMAXE"] = "Blackrock Spire",
	["BURNING FELGUARD"] = "Blackrock Spire",
	["CRYSTAL FANG"] = "Blackrock Spire",
	["GHOK BASHGUUD"] = "Blackrock Spire",
	["SPIRESTONE BATTLE LORD"] = "Blackrock Spire",
	["SPIRESTONE BUTCHER"] = "Blackrock Spire",
	["SPIRESTONE LORD MAGUS"] = "Blackrock Spire",
	["JED RUNEWATCHER"] = "Blackrock Spire",
	["BRUEGAL IRONKNUCKLE"] = "The Stockade",
	["MINER JOHNSON"] = "The Deadmines",
	["SKARR THE UNBREAKABLE"] = "Dire Maul",
	["MUSHGOG"] = "Dire Maul",
	["7:XT"] = "Badlands",
	["ACCURSED SLITHERBLADE"] = "Desolace",
	["ACHELLIOS THE BANISHED"] = "Thousand Needles",
	["AKKRILUS"] = "Ashenvale",
	["AKUBAR THE SEER"] = "Blasted Lands",
	["ALSHIRR BANEBREATH"] = "Felwood",
	["ANTILOS"] = "Azshara",
	["ANTILUS THE SOARER"] = "Feralas",
	["APOTHECARY FALTHIS"] = "Ashenvale",
	["ARAGA"] = "Alterac Mountains",
	["ARASH-ETHIS"] = "Feralas",
	["AZZERE THE SKYBLADE"] = "The Barrens",
	["BARNABUS"] = "Badlands",
	["BAYNE"] = "Tirisfal Glades",
	["BIG SAMRAS"] = "Hillsbrad Foothills",
	["BJARN"] = "Dun Morogh",
	["BLACKMOSS THE FETID"] = "Teldrassil",
	["BLOODROAR THE STALKER"] = "Feralas",
	["BOSS GALGOSH"] = "Loch Modan",
	["BOULDERHEART"] = "Redridge Mountains",
	["BRACK"] = "Westfall",
	["MARISA DU'PAIGE"] = "Westfall",
	["BRANCH SNAPPER"] = "Ashenvale",
	["BROKEN TOOTH"] = "Badlands",
	["BROKESPEAR"] = "The Barrens",
	["BURGLE EYE"] = "Dustwallow Marsh",
	["CARNIVOUS THE BREAKER"] = "Darkshore",
	["CHATTER"] = "Redridge Mountains",
	["CLACK THE REAVER"] = "Blasted Lands",
	["CLUTCHMOTHER ZAVAS"] = "Un'Goro Crater",
	["COMMANDER FELSTROM"] = "Duskwood",
	["CRANKY BENJ"] = "Alterac Mountains",
	["CREEPTHESS"] = "Hillsbrad Foothills",
	["CRIMSON ELITE"] = "Western Plaguelands",
	["CURSED CENTAUR"] = "Desolace",
	["CYCLOK THE MAD"] = "Tanaris",
	["DALARAN SPELLSCRIBE"] = "Silverpine Forest",
	["DARKMIST WIDOW"] = "Dustwallow Marsh",
	["DART"] = "Dustwallow Marsh",
	["DEATH FLAYER"] = "Durotar",
	["DEATH HOWL"] = "Felwood",
	["DEATHEYE"] = "Blasted Lands",
	["DEATHMAW"] = "Burning Steppes",
	["DEATHSPEAKER SELENDRE"] = "Eastern Plaguelands",
	["DEEB"] = "Tirisfal Glades",
	["DIAMOND HEAD"] = "Feralas",
	["DIGGER FLAMEFORGE"] = "The Barrens",
	["DISHU"] = "The Barrens",
	["DRAGONMAW BATTLEMASTER"] = "Wetlands",
	["DREADSCORN"] = "Blasted Lands",
	["DROGOTH THE ROAMER"] = "Dustwallow Marsh",
	["DUGGAN WILDHAMMER"] = "Eastern Plaguelands",
	["DUSKSTALKER"] = "Teldrassil",
	["DUSTWRAITH"] = "Zul'Farrak",
	["ECK'ALOM"] = "Ashenvale",
	["EDAN THE HOWLER"] = "Dun Morogh",
	["ENFORCER EMILGUND"] = "Mulgore",
	["ENGINEER WHIRLEYGIG"] = "The Barrens",
	["FALLEN CHAMPION"] = "Scarlet Monastery",
	["FARMER SOLLIDEN"] = "Tirisfal Glades",
	["FAULTY WAR GOLEM"] = "Searing Gorge",
	["FEDFENNEL"] = "Elwynn Forest",
	["FELLICENT'S SHADE"] = "Tirisfal Glades",
	["FENROS"] = "Duskwood",
	["FINGAT"] = "Swamp of Sorrows",
	["FIRECALLER RADISON"] = "Darkshore",
	["FLAGGLEMURK THE CRUEL"] = "Darkshore",
	["FOE REAPER 4000"] = "Westfall",
	["FOREMAN GRILLS"] = "The Barrens",
	["FOREMAN JERRIS"] = "Western Plaguelands",
	["FOREMAN MARCRID"] = "Western Plaguelands",
	["FOULMANE"] = "Western Plaguelands",
	["FURY SHELDA"] = "Teldrassil",
	["GARNEG CHARSKULL"] = "Wetlands",
	["GATEKEEPER RAGEROAR"] = "Azshara",
	["GENERAL FANGFERROR"] = "Azshara",
	["GEOLORD MOTTLE"] = "Durotar",
	["GEOMANCER FLINTDAGGER"] = "Arathi Highlands",
	["GEOPRIEST GUKK'ROK"] = "The Barrens",
	["GHOST HOWL"] = "Mulgore",
	["GIBBLESNIK"] = "Thousand Needles",
	["GIBBLEWILT"] = "Dun Morogh",
	["GIGGLER"] = "Desolace",
	["GILMORIAN"] = "Swamp of Sorrows",
	["GISH THE UNMOVING"] = "Eastern Plaguelands",
	["GLUGGLE"] = "Stranglethorn Vale",
	["GNARL LEAFBROTHER"] = "Feralas",
	["GNAWBONE"] = "Wetlands",
	["GOREFANG"] = "Silverpine Forest",
	["GORGON'OCH"] = "Burning Steppes",
	["GRAVIS SLIPKNOT"] = "Alterac Mountains",
	["GREAT FATHER ARCTIKUS"] = "Dun Morogh",
	["GREATER FIREBIRD"] = "Tanaris",
	["GRETHEER"] = "Silithus",
	["GRIMMAW"] = "Teldrassil",
	["GRIMTOOTH"] = "Alterac Valley",
	["GRIZLAK"] = "Loch Modan",
	["GRIZZLE SNOWPAW"] = "Winterspring",
	["GRUBTHOR"] = "Silithus",
	["GRUFF SWIFTBITE"] = "Elwynn Forest",
	["GRUKLASH"] = "Burning Steppes",
	["GRUNTER"] = "Blasted Lands",
	["HAARKA THE RAVENOUS"] = "Tanaris",
	["HAHK'ZOR"] = "Burning Steppes",
	["HAMMERSPINE"] = "Dun Morogh",
	["HARB FOULMOUNTAIN"] = "Thousand Needles",
	["HAYOC"] = "Dustwallow Marsh",
	["HED'MUSH THE ROTTING"] = "Eastern Plaguelands",
	["HEGGIN STONEWHISKER"] = "The Barrens",
	["HIGH GENERAL ABBENDIS"] = "Eastern Plaguelands",
	["HISSPERAK"] = "Desolace",
	["HUMAR THE PRIDELORD"] = "The Barrens",
	["HURICANIAN"] = "Silithus",
	["IRONBACK"] = "The Hinterlands",
	["IRONSPINE"] = "Scarlet Monastery",
	["JALINDE SUMMERDRAKE"] = "The Hinterlands",
	["JIMMY THE BLEEDER"] = "Alterac Mountains",
	["KASKK"] = "Desolace",
	["KAZON"] = "Redridge Mountains",
	["KOVORK"] = "Arathi Highlands",
	["KREGG KEELHAUL"] = "Tanaris",
	["KRELLACK"] = "Silithus",
	["KRETHIS SHADOWSPINNER"] = "Silverpine Forest",
	["KURMOKK"] = "Stranglethorn Vale",
	["LADY HEDERINE"] = "Winterspring",
	["LADY MOONGAZER"] = "Darkshore",
	["LADY SESSPIRA"] = "Azshara",
	["LADY SZALLAH"] = "Feralas",
	["LADY VESPIA"] = "Ashenvale",
	["LADY VESPIRA"] = "Darkshore",
	["LADY ZEPHRIS"] = "Hillsbrad Foothills",
	["LAPRESS"] = "Silithus",
	["LARGE LOCH CROCOLISK"] = "Loch Modan",
	["LEECH WIDOW"] = "Wetlands",
	["LEPRITHUS"] = "Westfall",
	["LICILLIN"] = "Darkshore",
	["LO'GROSH"] = "Alterac Mountains",
	["LORD ANGLER"] = "Dustwallow Marsh",
	["LORD CONDAR"] = "Loch Modan",
	["LORD DARKSCYTHE"] = "Eastern Plaguelands",
	["LORD MALATHROM"] = "Duskwood",
	["LORD MALDAZZAR"] = "Western Plaguelands",
	["LORD SAKRASIS"] = "Stranglethorn Vale",
	["LORD SINSLAYER"] = "Darkshore",
	["LOST ONE CHIEFTAIN"] = "Swamp of Sorrows",
	["LOST ONE COOK"] = "Swamp of Sorrows",
	["LOST SOUL"] = "Tirisfal Glades",
	["LUPOS"] = "Duskwood",
	["MA'RUK WYRMSCALE"] = "Wetlands",
	["MAGISTER HAWKHELM"] = "Azshara",
	["MAGOSH"] = "Loch Modan",
	["MAGRONOS THE UNYIELDING"] = "Blasted Lands",
	["MALFUNCTIONING REAVER"] = "Burning Steppes",
	["MALGIN BARLEYBREW"] = "The Barrens",
	["MASTER DIGGER"] = "Westfall",
	["MASTER FEARDRED"] = "Azshara",
	["MAZZRANACHE"] = "Mulgore",
	["MEZZIR THE HOWLER"] = "Winterspring",
	["MIRELOW"] = "Wetlands",
	["MIST HOWLER"] = "Ashenvale",
	["MOJO THE TWISTED"] = "Blasted Lands",
	["MOLOK THE CRUSHER"] = "Arathi Highlands",
	["MOLT THORN"] = "Swamp of Sorrows",
	["MONGRESS"] = "Felwood",
	["MORGAINE THE SLY"] = "Elwynn Forest",
	["MOTHER FANG"] = "Elwynn Forest",
	["MUAD"] = "Tirisfal Glades",
	["MUGGLEFIN"] = "Ashenvale",
	["MURDEROUS BLISTERPAW"] = "Tanaris",
	["NAL'TASZAR"] = "Stonetalon Mountains",
	["NARAXIS"] = "Duskwood",
	["NARG THE TASKMASTER"] = "Elwynn Forest",
	["NEFARU"] = "Duskwood",
	["NIMAR THE SLAYER"] = "Arathi Highlands",
	["OAKPAW"] = "Ashenvale",
	["OLD CLIFF JUMPER"] = "The Hinterlands",
	["OLD GRIZZLEGUT"] = "Feralas",
	["OLD VICEJAW"] = "Silverpine Forest",
	["OLM THE WISE"] = "Felwood",
	["OMGORN THE LOST"] = "Tanaris",
	["OOZEWORM"] = "Dustwallow Marsh",
	["PRIDEWING PATRIARCH"] = "Stonetalon Mountains",
	["PRINCE KELLEN"] = "Desolace",
	["PRINCE NAZJAK"] = "Arathi Highlands",
    ["PRINCE RAZE"] = "Ashenvale",
    ["PUTRIDIUS"] = "Western Plaguelands",
    ["QIROT"] = "Feralas",
    ["RAGEPAW"] = "Felwood",
    ["RAK'SHIRI"] = "Winterspring",
    ["RANGER LORD HAWKSPEAR"] = "Eastern Plaguelands",
    ["RATHORIAN"] = "The Barrens",
    ["RAVAGE"] = "Blasted Lands",
    ["RAVASAUR MATRIARCH"] = "Un'Goro Crater",
    ["RAVENCLAW REGENT"] = "Silverpine Forest",
    ["RAZORMAW MATRIARCH"] = "Wetlands",
    ["RAZORTALON"] = "The Hinterlands",
    ["REKK'TILAC"] = "Searing Gorge",
    ["RESSAN THE NEEDLER"] = "Tirisfal Glades",
    ["RETHEROKK THE BERSERKER"] = "The Hinterlands",
    ["RIBCHASER"] = "Redridge Mountains",
    ["RIPPA"] = "Stranglethorn Vale",
    ["RIPSCALE"] = "Dustwallow Marsh",
    ["RO'BARK"] = "Hillsbrad Foothills",
    ["ROHH THE SILENT"] = "Redridge Mountains",
    ["ROLOCH"] = "Stranglethorn Vale",
    ["RORGISH JOWL"] = "Ashenvale",
    ["ROT HIDE BRUISER"] = "Silverpine Forest",
    ["RUMBLER"] = "Badlands",
    ["SANDARR DUNEREAVER"] = "Zul'farrak",
    ["SCALD"] = "Searing Gorge",
    ["SCALE BELLY"] = "Stranglethorn Vale",
    ["SCARGIL"] = "Hillsbrad Foothills",
    ["SCARLET INTERROGATOR"] = "Western Plaguelands",
    ["SCARLET JUDGE"] = "Western Plaguelands",
    ["SCARLET SMITH"] = "Western Plaguelands",
    ["SEEKER AQUALON"] = "Redridge Mountains",
    ["SENTINEL AMARASSAN"] = "Stonetalon Mountains",
    ["SERGEANT BRASHCLAW"] = "Westfall",
    ["SETIS"] = "Silithus",
    ["SEWER BEAST"] = "Stormwind City",
    ["SHADOWCLAW"] = "Darkshore",
    ["SHADOWFORGE COMMANDER"] = "Badlands",
    ["SHANDA THE SPINNER"] = "Loch Modan",
    ["SHLEIPNARR"] = "Searing Gorge",
    ["SILITHID HARVESTER"] = "The Barrens",
    ["SILITHID RAVAGER"] = "Thousand Needles",
    ["SINGER"] = "Arathi Highlands",
    ["SKHOWL"] = "Alterac Mountains",
    ["SLARK"] = "Westfall",
    -- ["SLAVE MASTER BLACKHEART"] = "Searing Gorge", -- underground mob, may wanna disable
    ["SLUDGE BEAST"] = "The Barrens",
    ["SLUDGINN"] = "Wetlands",
    ["SMOLDAR"] = "Searing Gorge",
    ["SNAGGLESPEAR"] = "Mulgore",
    ["SNARLER"] = "Feralas",
    ["SNARLFLARE"] = "Redridge Mountains",
    ["SNARLMANE"] = "Silverpine Forest",
    ["SNORT THE HECKLER"] = "The Barrens",
    ["SORIID THE DEVOURER"] = "Tanaris",
    ["SPITEFLAYER"] = "Blasted Lands",
    ["SQUIDDIC"] = "Redridge Mountains",
    ["SRI'SKULK"] = "Tirisfal Glades",
    ["STONE FURY"] = "Alterac Mountains",
    ["STONEARM"] = "The Barrens",
    ["STRIDER CLUTCHMOTHER"] = "Darkshore",
    ["TERRORSPARK"] = "Burning Steppes",
    ["TERROWULF PACKLORD"] = "Ashenvale",
    ["THAURIS BALGARR"] = "Burning Steppes",
    -- ["THE CLEANER"] = "Eastern Plaguelands", -- doesnt drop anything and too much hp.
    ["THE EVALCHARR"] = "Azshara",
    ["THE HUSK"] = "Western Plaguelands",
    ["THE ONGAR"] = "Felwood",
    ["THE RAKE"] = "Mulgore",
    ["THE RAZZA"] = "Dire Maul",
    ["THE REAK"] = "The Hinterlands",
    ["THE ROT"] = "Dustwallow Marsh",
    ["THREGGIL"] = "Teldrassil",
    ["THUNDERSTOMP"] = "The Barrens",
    ["THUROS LIGHTFINGERS"] = "Elwynn Forest",
    ["TIMBER"] = "Dun Morogh",
    ["TORMENTED SPIRIT"] = "Tirisfal Glades",
    ["TWILIGHT LORD EVERUN"] = "Silithus",
    ["UHK'LOC"] = "Un'Goro Crater",
    ["URSOL'LOK"] = "Ashenvale",
    ["URUSON"] = "Teldrassil",
    ["VARO'THEN'S GHOST"] = "Azshara",
    ["VENGEFUL ANCIENT"] = "Stonetalon Mountains",
    ["VERIFONIX"] = "Stranglethorn Vale",
    ["VOLCHAN"] = "Burning Steppes",
    ["VULTROS"] = "Westfall",
    ["WAR GOLEM"] = "Badlands",
    ["WARLORD KOLKANIS"] = "Durotar",
    ["WARLORD THRESH'JIN"] = "Eastern Plaguelands",
    ["WATCH COMMANDER ZALAPHIL"] = "Durotar",
    ["WITHERHEART THE STALKER"] = "The Hinterlands",
    ["ZALAS WITHERBARK"] = "Arathi Highlands",
    ["ZORA"] = "Silithus",
    ["ZUL'BRIN WARPBRANCH"] = "Eastern Plaguelands",
    ["ZUL'AREK HATEFOWLER"] = "The Hinterlands",
    -- Thanks to Macumba for finding these rares
    -- ["NERUBIAN OVERSEER"] = "Eastern Plaguelands", -- doesnt drop anything worth and too much hp.
	["DIGMASTER SHOVELPHLANGE"] = "Badlands",
	-- ["SCARSHIELD QUARTERMASTER"] = "Blackrock Mountain", -- doesnt drop anything worth
	["THE BEHEMOTH"] = "Blackrock Mountain",
	["TREGLA"] = "Eversong Woods",
	["BRAINWASHED NOBLE"] = "The Deadmines",
	["TRIGORE THE LASHER"] = "Wailing Caverns",
	["BOAHN"] = "Wailing Caverns",
	["CRUSTY"] = "Desolace",
	["ZEKKIS"] = "Temple of Atal'Hakkar",
	["VEYZHAK THE CANNIBAL"] = "Temple of Atal'Hakkar",
}
-- RARE_SPAWNS_FR_END
