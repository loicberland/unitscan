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
	["AZUROUS"] = "Berceau-de-l'Hiver",
	["GÉNÉRAL COLBATANN"] = "Berceau-de-l'Hiver",
	["KASHOCH LE RAVAGEUR"] = "Berceau-de-l'Hiver",
	["DAME HEDERINE"] = "Berceau-de-l'Hiver",
	["ALSHIRR SOUFFLÉAU"] = "Gangrebois",
	["DESSECUS"] = "Gangrebois",
	["IMMOLATUS"] = "Gangrebois",
	["MONNOS L'ANCIEN"] = "Azshara",
	["BARBE-D'ÉCAILLES"] = "Azshara",
	["FRÈRE CORVICHÊNE"] = "Les Serres-Rocheuses",
	["CONTREMAÎTRE GRÉEUR"] = "Les Serres-Rocheuses",
	["SŒUR RIVEN"] = "Les Serres-Rocheuses",
	["AILES DU DÉSESPOIR"] = "Les Serres-Rocheuses",
	["SOUS-CHEF FOUETTECROC"] = "Les Serres-Rocheuses",
	["AEAN ONDEVIVE"] = "Les Tarides",
	["AMBASSADEUR RAGESANG"] = "Les Tarides",
	["BRONTUS"] = "Les Tarides",
	["CAPITAINE GEROGG MARTÈLORTEIL"] = "Les Tarides",
	["ANCIENNE MYSTIQUE TRANCHEGROIN"] = "Les Tarides",
	["GESHARAHAN"] = "Les Tarides",
	["HAGG PLAIE-DES-TAURENS"] = "Les Tarides",
	["HANNAH FEUILLELAME"] = "Les Tarides",
	["MARCUS BEL"] = "Les Tarides",
	["ROCHELANCE"] = "Les Tarides",
	["SŒUR RATHTALON"] = "Les Tarides",
	["VIF-CRINS"] = "Les Tarides",
	["PEAU-PIQUANTE POURCEGART"] = "Les Tarides",
	["TAKK LE BONDISSEUR"] = "Les Tarides",
	["THORA PENNELUNE"] = "Les Tarides",
	["CAPITAINE PLATE-DÉFENSE"] = "Durotar",
	["GANGRETISSEUR ARROGG"] = "Durotar",
	["SOUFRESANG"] = "Marécage d'Âprefange",
	["SŒUR CINGLEHAINE"] = "Mulgore",
	["TRANCHECOEUR"] = "Mille pointes",
	["FERREGARD L’INVINCIBLE"] = "Mille pointes",
	["DARDEUR"] = "Mille pointes",
	["JIN'ZALLAH PORTE-SABLE"] = "Tanaris",
	["CHEF DE GUERRE KRAZZILAK"] = "Tanaris",
	["GRUFF"] = "Cratère d'Un'Goro",
	["ROI MOSH"] = "Cratère d'Un'Goro",
	["REX ASHIL"] = "Silithus",
	["BOURREAU ÉCARLATE"] = "Maleterres de l'ouest",
	["GRAND PRÊTRE ÉCARLATE"] = "Maleterres de l'ouest",
	["TAMRA FOUDREPIQUE"] = "Contreforts de Hautebrande",
	["NARILLASANZ"] = "Montagnes d'Alterac",
	["GRIMUNGOUS"] = "Les Hinterlands",
	["MITH'RETHIS L'ENCHANTEUR"] = "Les Hinterlands",
	["DARBEL MONTROSE"] = "Hautes-terres d'Arathi",
	["SOUILLEBEDON"] = "Hautes-terres d'Arathi",
	["RUUL UNEPIERRE"] = "Hautes-terres d'Arathi",
	["EMOGG LE BROYEUR"] = "Loch Modan",
	["GOLEM DE SIÈGE"] = "Terres ingrates",
	["GÉNÉRALISSIME MASTROGONDE"] = "Gorge des Vents brûlant",
	["HEMATOS"] = "Steppes ardentes",
	["SEIGNEUR-CAPITAINE WYRMAK"] = "Marais des Chagrins",
	["JADE"] = "Marais des Chagrins",
	["GRANDE PRÊTRESSE HAI'WATNA"] = "Vallée de Strangleronce",
	["BOUCHER MOSH'OGG"] = "Vallée de Strangleronce",
	["ANATHEMUS"] = "Terres ingrates",
	["ZARICOTL"] = "Terres ingrates",
	["DRAGON FÉERIQUE DÉVIANT"] = "Cavernes des lamentations",
	["MESHLOK LE MOISSONNEUR"] = "Maraudon",
	["CHASSEUR AVEUGLE"] = "Kraal de Tranchebauge",
	["IMPLORATEUR DE LA TERRE HALMGAR"] = "Kraal de Tranchebauge",
	["LANCEUR DE TRANCHEBAUGE"] = "Kraal de Tranchebauge",
	["ZERILLIS"] = "Zul'Farrak",
	["AZSHIR LE SANS-SOMMEIL"] = "Monastère écarlate",
	["CHANTELOGE FORRESTIN"] = "Stratholme",
	["KRÂN"] = "Stratholme",
	["ECHINE-DE-PIERRE"] = "Stratholme",
	["CAPITAINE LIGEMORT"] = "Donjon d'Ombrecroc",
	["AMBASSADEUR SOMBREFER"] = "Gnomeregan",
	["SEIGNEUR ROCCOR"] = "Profondeurs de Rochenoire",
	["PANZOR L'INVINCIBLE"] = "Profondeurs de Rochenoire",
	["PYROMANCIEN BLÉ-DU-SAVOIR"] = "Profondeurs de Rochenoire",
	["VEREK"] = "Profondeurs de Rochenoire",
	["GARDIEN STILGISS"] = "Profondeurs de Rochenoire",
	["BANNOK HACHE-SINISTRE"] = "Pic Rochenoire",
	["GANGREGARDE ARDENT"] = "Pic Rochenoire",
	["CROC CRISTALLIN"] = "Pic Rochenoire",
	["GHOK BOUNNEBAFFE"] = "Pic Rochenoire",
	["SEIGNEUR DE BATAILLE PIERRE-DU-PIC"] = "Pic Rochenoire",
	["BOUCHER PIERRE-DU-PIC"] = "Pic Rochenoire",
	["SEIGNEUR MAGUS PIERRE-DU-PIC"] = "Pic Rochenoire",
	["JED GUETTE-RUNES"] = "Pic Rochenoire",
	["BRUEGAL POING-DE-FER"] = "La Prison",
	["MINEUR JOHNSON"] = "Les Mortemines",
	["BÂLHAFR L'INVAINCU"] = "Hache-tripes",
	["MUSHGOG"] = "Hache-tripes",
	["7:XT"] = "Terres ingrates",
	["ONDULAME MAUDIT"] = "Désolace",
	["ACHELLIOS LE BANNI"] = "Mille pointes",
	["AKKRILUS"] = "Orneval",
	["AKUBAR LE PROPHÈTE"] = "Terres foudroyées",
	["ANTILOS"] = "Azshara",
	["ANTILUS LE PLANEUR"] = "Féralas",
	["APOTHICAIRE FALTHIS"] = "Orneval",
	["ARAGA"] = "Montagnes d'Alterac",
	["ARASH-ETHIS"] = "Féralas",
	["AZZERE LA LAME CÉLESTE"] = "Les Tarides",
	["BARNABUS"] = "Terres ingrates",
	["BAYNE"] = "Clairières de Tirisfal",
	["GROS SAMRAS"] = "Contreforts de Hautebrande",
	["BJARN"] = "Dun Morogh",
	["NOIREMOUSSE LE FÉTIDE"] = "Teldrassil",
	["RUGISSANG LE TRAQUEUR"] = "Féralas",
	["BOSS GALGOSH"] = "Loch Modan",
	["ROCHECOEUR"] = "Les Carmines",
	["BRACK"] = "Marche de l'Ouest",
	["MARISA DU'PAIGE"] = "Marche de l'Ouest",
	["BRISE-BRANCHE"] = "Orneval",
	["BRÈCHEDENT"] = "Terres ingrates",
	["BRISE-ÉPIEU"] = "Les Tarides",
	["PIQUE-LES-YEUX"] = "Marécage d'Âprefange",
	["CARNIVOUS LE CASSEUR"] = "Sombrivage",
	["CLIQUETEUSE"] = "Les Carmines",
	["CLACK LE SACCAGEUR"] = "Terres foudroyées",
	["MATRIARCHE ZAVAS"] = "Cratère d'Un'Goro",
	["COMMANDANT GANGRETROMBE"] = "Bois de la Pénombre",
	["BENJ LE TEIGNEUX"] = "Montagnes d'Alterac",
	["INSINUEUSE"] = "Contreforts de Hautebrande",
	["ELITE CRAMOISIE"] = "Maleterres de l'ouest",
	["CENTAURE MAUDIT"] = "Désolace",
	["CYCLOK LE FOL"] = "Tanaris",
	["COPISTE DE DALARAN"] = "Forêt des Pins argentés",
	["VEUVE DE SOMBREBRUME"] = "Marécage d'Âprefange",
	["FLÈCHE"] = "Marécage d'Âprefange",
	["ECORCHEUR MORTEL"] = "Durotar",
	["SERGENT CURTIS"] = "Durotar",
	["HURLEMORT"] = "Gangrebois",
	["OEIL-DE-MORT"] = "Terres foudroyées",
	["GUEULE-DU-TRÉPAS"] = "Steppes ardentes",
	["NÉCRORATEUR SELENDRE"] = "Maleterres de l'est",
	["DEEB"] = "Clairières de Tirisfal",
	["TÊTE-DE-DIAMANT"] = "Féralas",
	["TERRASSIER FORGEFLAMME"] = "Les Tarides",
	["DISHU"] = "Les Tarides",
	["MAÎTRE DE GUERRE GUEULE-DE-DRAGON"] = "Les Paluns",
	["DÉRISEFFROI"] = "Terres foudroyées",
	["DROGOTH LE VAGABOND"] = "Marécage d'Âprefange",
	["DUGGAN MARTEAU-HARDI"] = "Maleterres de l'est",
	["TRAQUEUR DU CRÉPUSCULE"] = "Teldrassil",
	["AME EN PEINE POUDREUSE"] = "Zul'Farrak",
	["ECK'ALOM"] = "Orneval",
	["EDAN LE HURLEUR"] = "Dun Morogh",
	["MASSACREUR EMILGUND"] = "Mulgore",
	["INGÉNIEUR TOURBICOTON"] = "Les Tarides",
	["CHAMPION DÉCHU"] = "Monastère écarlate",
	["FERMIER DE SOLLIDEN"] = "Clairières de Tirisfal",
	["GOLEM DE GUERRE DÉFAILLANT"] = "Gorge des Vents brûlant",
	["FENOUILLARD"] = "Forêt d'Elwynn",
	["OMBRE DE FELLICENT"] = "Clairières de Tirisfal",
	["FENROS"] = "Bois de la Pénombre",
	["FINGAT"] = "Marais des Chagrins",
	["MANDEFEU RADISON"] = "Sombrivage",
	["FLAGGLEMURK LE CRUEL"] = "Sombrivage",
	["DÉCOUPEUR 4000"] = "Marche de l'Ouest",
	["CONTREMAÎTRE GRILLS"] = "Les Tarides",
	["CONTREMAÎTRE JERRIS"] = "Maleterres de l'ouest",
	["CONTREMAÎTRE MARCRID"] = "Maleterres de l'ouest",
	["VILCRIN"] = "Maleterres de l'ouest",
	["FURIE SHELDA"] = "Teldrassil",
	["GARNEG GRILLE-CRÂNE"] = "Les Paluns",
	["PORTIER HURLERAGE"] = "Azshara",
	["GÉNÉRAL CROCDANGOIFFE"] = "Azshara",
	["GÉOMAÎTRESSE MOUCHETTE"] = "Durotar",
	["GÉOMANCIEN DAGUE-DE-SILEX"] = "Hautes-terres d'Arathi",
	["GÉOPRÊTRESSE GUKK'ROK"] = "Les Tarides",
	["HURLEUR FANTOMATIQUE"] = "Mulgore",
	["MARGOUILLOCHE"] = "Mille pointes",
	["MARGOUILLEUR"] = "Dun Morogh",
	["GLOUSSE"] = "Désolace",
	["GILMORIAN"] = "Marais des Chagrins",
	["GISH L'IMMOBILE"] = "Maleterres de l'est",
	["GLOUGLOUG"] = "Vallée de Strangleronce",
	["GNARL FRÈREFEUILLES"] = "Féralas",
	["RONGE-LES-OS"] = "Les Paluns",
	["CROQUETRIPE"] = "Forêt des Pins argentés",
	["GORGON'OCH"] = "Steppes ardentes",
	["GRAVIS LECOLLET"] = "Montagnes d'Alterac",
	["GRAND-PÈRE ARCTIKUS"] = "Dun Morogh",
	["GRAND OISEAU DE FEU"] = "Tanaris",
	["GRETHEER"] = "Silithus",
	["MORNEGUEULE"] = "Teldrassil",
	["MÂCHINISTRE"] = "Alterac Valley",
	["GRIZLAK"] = "Loch Modan",
	["GRISON NEIGEPATTE"] = "Berceau-de-l'Hiver",
	["GRUBTHOR"] = "Silithus",
	["GRUFF MORD-VITE"] = "Forêt d'Elwynn",
	["GRUKLASH"] = "Steppes ardentes",
	["GRUNTER"] = "Terres foudroyées",
	["HAARKA LE FÉROCE"] = "Tanaris",
	["HAHK'ZOR"] = "Steppes ardentes",
	["MARTELLÉCHINE"] = "Dun Morogh",
	["HARB MONT-SOUILLÉ"] = "Mille pointes",
	["HAYOC"] = "Marécage d'Âprefange",
	["HED'MUSH LE POURRISSANT"] = "Maleterres de l'est",
	["HEGGIN MOUSTACHE-DE-PIERRE"] = "Les Tarides",
	["GRAND GÉNÉRAL ABBENDIS"] = "Maleterres de l'est",
	["HISSPERAK"] = "Désolace",
	["HUMAR LE FIER"] = "Les Tarides",
	["OURAGANIEN"] = "Silithus",
	["DOS-DE-FER"] = "Les Hinterlands",
	["ECHINE-DE-FER"] = "Monastère écarlate",
	["JALINDE DRAKE-D'ÉTÉ"] = "Les Hinterlands",
	["JIMMY LE SAIGNANT"] = "Montagnes d'Alterac",
	["KASKK"] = "Désolace",
	["KAZON"] = "Les Carmines",
	["KOVORK"] = "Hautes-terres d'Arathi",
	["KREGG SOULAQUILLE"] = "Tanaris",
	["KRELLACK"] = "Silithus",
	["KRETHIS TISSOMBRE"] = "Forêt des Pins argentés",
	["KURMOKK"] = "Vallée de Strangleronce",
	["DAME HEDERINE"] = "Berceau-de-l'Hiver",
	["DAME MIRELUNE"] = "Sombrivage",
	["DAME SESSPIRA"] = "Azshara",
	["DAME SZALLAH"] = "Féralas",
	["DAME VESPIA"] = "Orneval",
	["DAME VESPIRA"] = "Sombrivage",
	["DAME ZEPHRIS"] = "Contreforts de Hautebrande",
	["LAPRESS"] = "Silithus",
	["GRAND CROCILISQUE DU LOCH"] = "Loch Modan",
	["VEUVE SANGUINE"] = "Les Paluns",
	["LEPRITHUS"] = "Marche de l'Ouest",
	["LICILLIN"] = "Sombrivage",
	["LO'GROSH"] = "Montagnes d'Alterac",
	["SEIGNEUR BAUDROIE"] = "Marécage d'Âprefange",
	["SEIGNEUR CONDAR"] = "Loch Modan",
	["SEIGNEUR SOMBREFAUX"] = "Maleterres de l'est",
	["SEIGNEUR MALATHROM"] = "Bois de la Pénombre",
	["SEIGNEUR MALDAZZAR"] = "Maleterres de l'ouest",
	["SEIGNEUR SAKRASIS"] = "Vallée de Strangleronce",
	["SEIGNEUR SALVASSIO"] = "Sombrivage",
	["CHEF PERDU"] = "Marais des Chagrins",
	["CUISINIER PERDU"] = "Marais des Chagrins",
	["AME ÉGARÉE"] = "Clairières de Tirisfal",
	["LUPOS"] = "Bois de la Pénombre",
	["MA'RUK WYRMÉCAILLE"] = "Les Paluns",
	["MAGISTÈRE FALCOIFFE"] = "Azshara",
	["MAGOSH"] = "Loch Modan",
	["MAGRONOS L'INFLEXIBLE"] = "Terres foudroyées",
	["SACCAGEUR DÉFECTUEUX"] = "Steppes ardentes",
	["MALGIN BRASSELORGE"] = "Les Tarides",
	["MAÎTRE TERRASSIER"] = "Marche de l'Ouest",
	["MAÎTRE TROUILLEFFROI"] = "Azshara",
	["MAZZRANACHE"] = "Mulgore",
	["MEZZIR LE HURLEUR"] = "Berceau-de-l'Hiver",
	["BAS-BOUEUX"] = "Les Paluns",
	["HURLEUR DES BRUMES"] = "Orneval",
	["MOJO LE TORDU"] = "Terres foudroyées",
	["MOLOK L’ANÉANTISSEUR"] = "Hautes-terres d'Arathi",
	["ROUGERONCE"] = "Marais des Chagrins",
	["MONGRESS"] = "Gangrebois",
	["MORGAINE LA RUSÉE"] = "Forêt d'Elwynn",
	["MÈRE CROC"] = "Forêt d'Elwynn",
	["MUAD"] = "Clairières de Tirisfal",
	["MOLDAILERON"] = "Orneval",
	["BRÛLEPATTE MEURTRIER"] = "Tanaris",
	["NAL'TASZAR"] = "Les Serres-Rocheuses",
	["NARAXIS"] = "Bois de la Pénombre",
	["NARG LE SOUS-CHEF"] = "Forêt d'Elwynn",
	["NEFARU"] = "Bois de la Pénombre",
	["NIMAR LE POURFENDEUR"] = "Hautes-terres d'Arathi",
	["CHÊNEPATTE"] = "Orneval",
	["VIEUX SAUTE-FALAISE"] = "Les Hinterlands",
	["VIEUX GRISEBEDAINE"] = "Féralas",
	["VIEUX VILE MÂCHOIRE"] = "Forêt des Pins argentés",
	["OLM LA SAGE"] = "Gangrebois",
	["OMGORN L'EGARÉ"] = "Tanaris",
	["VER DE LIMON"] = "Marécage d'Âprefange",
	["PATRIARCHE AILE-FIÈRE"] = "Les Serres-Rocheuses",
	["PRINCE KELLEN"] = "Désolace",
	["PRINCE NAZJAK"] = "Hautes-terres d'Arathi",
    ["PRINCE RAZE"] = "Orneval",
    ["PUTRIDIUS"] = "Maleterres de l'ouest",
    ["QIROT"] = "Féralas",
    ["RAGEPATTE"] = "Gangrebois",
    ["RAK'SHIRI"] = "Berceau-de-l'Hiver",
    ["SEIGNEUR FORESTIER EPERLANCE"] = "Maleterres de l'est",
    ["RATHORIAN"] = "Les Tarides",
    ["RAVAGE"] = "Terres foudroyées",
    ["MATRIARCHE RAVASAURE"] = "Cratère d'Un'Goro",
    ["RÉGENT SERRES-DE-CORBEAU"] = "Forêt des Pins argentés",
    ["MATRIARCHE TRANCHEGUEULES"] = "Les Paluns",
    ["TRANCHESERRE"] = "Les Hinterlands",
    ["REKK'TILAC"] = "Gorge des Vents brûlant",
    ["RESSAN LE HARCELEUR"] = "Clairières de Tirisfal",
    ["RETHEROKK LE BERSERKER"] = "Les Hinterlands",
    ["CHASSECÔTES"] = "Les Carmines",
    ["RIPPA"] = "Vallée de Strangleronce",
    ["ARRACHÉCAILLE"] = "Marécage d'Âprefange",
    ["RO'BARK"] = "Contreforts de Hautebrande",
    ["ROHH LE SILENCIEUX"] = "Les Carmines",
    ["ROLOCH"] = "Vallée de Strangleronce",
    ["JOUFFLU LE CROQUANT"] = "Orneval",
    ["COGNEUR POIL-PUTRIDE"] = "Forêt des Pins argentés",
    ["GRONDEUR"] = "Terres ingrates",
    ["SANDARR RAVADUNE"] = "Zul'farrak",
    ["BRÛLAR"] = "Gorge des Vents brûlant",
    ["VENTRÉCAILLE"] = "Vallée de Strangleronce",
    ["SCARGIL"] = "Contreforts de Hautebrande",
    ["INQUISITEUR ÉCARLATE"] = "Maleterres de l'ouest",
    ["JUGE ÉCARLATE"] = "Maleterres de l'ouest",
    ["FORGERON ÉCARLATE"] = "Maleterres de l'ouest",
    ["AQUALON LE CHERCHEUR"] = "Les Carmines",
    ["SENTINELLE AMARASSAN"] = "Les Serres-Rocheuses",
    ["SERGENT PROMPTEGRIFFE"] = "Marche de l'Ouest",
    ["SETIS"] = "Silithus",
    ["BÊTE DES ÉGOUTS"] = "Hurlevent",
    ["OMBREGRIFFE"] = "Sombrivage",
    ["COMMANDANT OMBREFORGE"] = "Terres ingrates",
    ["SHANDA LA TISSEUSE"] = "Loch Modan",
    ["SHLEIPNARR"] = "Gorge des Vents brûlant",
    ["MOISSONNEUR SILITHIDE"] = "Les Tarides",
    ["RAVAGEUR SILITHIDE"] = "Mille pointes",
    ["SINGER"] = "Hautes-terres d'Arathi",
    ["GRYBOU"] = "Montagnes d'Alterac",
    ["SLARK"] = "Marche de l'Ouest",
	-- ["MAÎTRE DES ESCLAVES COEUR-NOIR"] = "Gorge des Vents brûlant", -- underground mob, may wanna disable
    ["LIMACE BESTIALE"] = "Les Tarides",
    ["BOUILLASSEUX"] = "Les Paluns",
    ["FUMAR"] = "Gorge des Vents brûlant",
    ["TRAVÉPIEU"] = "Mulgore",
    ["GROGNEUR"] = "Féralas",
    ["GRONDEFUSE"] = "Les Carmines",
    ["GRONDECRIN"] = "Forêt des Pins argentés",
    ["NIFLE LA MOQUEUSE"] = "Les Tarides",
    ["SORIID LE DÉVOREUR"] = "Tanaris",
    ["ECORCHEBILE"] = "Terres foudroyées",
    ["SQUIDDIC"] = "Les Carmines",
    ["SRI'SKULK"] = "Clairières de Tirisfal",
    ["FURIE-DE-PIERRE"] = "Montagnes d'Alterac",
    ["BRAS-DE-PIERRE"] = "Les Tarides",
    ["MATRIARCHE TROTTEUSE"] = "Sombrivage",
    ["LUEUR TERRIFIANTE"] = "Steppes ardentes",
    ["CHEF DE MEUTE FRAYELOUP"] = "Orneval",
    ["THAURIS BALGARR"] = "Steppes ardentes",
    -- ["LE NETTOYEUR"] = "Maleterres de l'est",  -- doesnt drop anything and too much hp.
    ["L'EVALCHARR"] = "Azshara",
    ["LA BOGUE"] = "Maleterres de l'ouest",
    ["L'ONGAR"] = "Gangrebois",
    ["LE GRIFFU"] = "Mulgore",
    ["LA RAZZA"] = "Hache-tripes",
    ["LE JONC"] = "Les Hinterlands",
    ["LA POURRITURE"] = "Marécage d'Âprefange",
    ["THREGGIL"] = "Teldrassil",
    ["GRONDETERRE"] = "Les Tarides",
    ["THUROS DOIGTS-AGILES"] = "Forêt d'Elwynn",
    ["GRUMEUX"] = "Dun Morogh",
    ["ESPRIT TOURMENTÉ"] = "Clairières de Tirisfal",
    ["SEIGNEUR DU CRÉPUSCULE EVERUN"] = "Silithus",
    ["UHK'LOC"] = "Cratère d'Un'Goro",
    ["URSOL'LOK"] = "Orneval",
    ["URUSON"] = "Teldrassil",
    ["FANTÔME DE VARO'THEN"] = "Azshara",
    ["ANCIEN VENGEUR"] = "Les Serres-Rocheuses",
    ["DROLATIX"] = "Vallée de Strangleronce",
    ["VOLCHAN"] = "Steppes ardentes",
    ["VULTROS"] = "Marche de l'Ouest",
    ["GOLEM DE GUERRE"] = "Terres ingrates",
    ["SEIGNEUR DE GUERRE KOLKANIS"] = "Durotar",
    ["SEIGNEUR DE GUERRE THRESH'JIN"] = "Maleterres de l'est",
    ["COMMANDANT DE LA GARDE ZALAPHIL"] = "Durotar",
    ["FLÉTRICOEUR LE TRAQUEUR"] = "Les Hinterlands",
    ["ZALAS FÂNÉCORCE"] = "Hautes-terres d'Arathi",
    ["ZORA"] = "Silithus",
    ["ZUL'BRIN VOILEBRANCHE"] = "Maleterres de l'est",
    ["ZUL'AREK VOLAILLAÎNE"] = "Les Hinterlands",
    -- Thanks to Macumba for finding these rares.	
    -- ["SURVEILLANT NÉRUBIEN"] = "Maleterres de l'est", -- doesnt drop anything worth and too much hp.
	["MAÎTRE DES FOUILLES PELLAPHLANGE"] = "Terres ingrates",
	-- ["INTENDANT DU BOUCLIER BALAFRÉ"] = "Mont Rochenoire", -- doesnt drop anything worth
	["LE BÉHÉMOTH"] = "Mont Rochenoire",
	["TREGLA"] = "Bois des Chants éternels",
	["NOBLE MANIPULÉ"] = "Les Mortemines",
	["TRIGORE LE FLAGELLEUR"] = "Cavernes des lamentations",
	["BOAHN"] = "Cavernes des lamentations",
	["CROUSTILLE"] = "Désolace",
	["ZEKKIS"] = "Le temple d'Atal'Hakkar",
	["VEYZHAK LE CANNIBALE"] = "Le temple d'Atal'Hakkar",
}
-- RARE_SPAWNS_FR_END
