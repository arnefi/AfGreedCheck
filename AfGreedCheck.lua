-----------------------------------------------------------------------------------------------
-- Client Lua Script for AfGreedCheck
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"

 
-----------------------------------------------------------------------------------------------
-- AfGreedCheck Module Definition
-----------------------------------------------------------------------------------------------

local AfGreedCheck = {} 

 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------

local AfGreedVersion = "@project-version@"

local iEmpty    = 0
local iNeed     = 1
local iGreed    = 2
local iPass     = 3
local iWonNeed  = 4
local iWonGreed = 5

local ksSprite = {
	[iEmpty]    = "CRB_CharacterCreateSprites:sprCharC_ClassFooterIconWhite",
	[iNeed]     = "IconSprites:Icon_MapNode_Map_Trainer",
	[iGreed]    = "IconSprites:Icon_MapNode_Map_Vendor",
	[iPass]     = "CRB_CharacterCreateSprites:sprCharC_ClassFooterIconDisabled",
	[iWonNeed]  = "IconSprites:Icon_MapNode_Map_Trainer",
	[iWonGreed] = "IconSprites:Icon_MapNode_Map_Vendor",
}

local ktEvalColors = {
	[Item.CodeEnumItemQuality.Inferior]  = ApolloColor.new("ItemQuality_Inferior"),
	[Item.CodeEnumItemQuality.Average] 	 = ApolloColor.new("ItemQuality_Average"),
	[Item.CodeEnumItemQuality.Good] 	 = ApolloColor.new("ItemQuality_Good"),
	[Item.CodeEnumItemQuality.Excellent] = ApolloColor.new("ItemQuality_Excellent"),
	[Item.CodeEnumItemQuality.Superb] 	 = ApolloColor.new("ItemQuality_Superb"),
	[Item.CodeEnumItemQuality.Legendary] = ApolloColor.new("ItemQuality_Legendary"),
	[Item.CodeEnumItemQuality.Artifact]	 = ApolloColor.new("ItemQuality_Artifact")
}

local ktEvalQualities = {
	[Item.CodeEnumItemQuality.Inferior]  = "BK3:UI_BK3_ItemQualityGrey",
	[Item.CodeEnumItemQuality.Average]   = "BK3:UI_BK3_ItemQualityWhite",
	[Item.CodeEnumItemQuality.Good]      = "BK3:UI_BK3_ItemQualityGreen",
	[Item.CodeEnumItemQuality.Excellent] = "BK3:UI_BK3_ItemQualityBlue",
	[Item.CodeEnumItemQuality.Superb]    = "BK3:UI_BK3_ItemQualityPurple",
	[Item.CodeEnumItemQuality.Legendary] = "BK3:UI_BK3_ItemQualityOrange",
	[Item.CodeEnumItemQuality.Artifact]  = "BK3:UI_BK3_ItemQualityMagenta"
}

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------

function AfGreedCheck:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

	o.GroupSize = 0
	o.Group = {}
	o.VirtualGroup = {}
	o.VirtualGroupSize = 0
	o.LootCache = {}
	o.Settings = { -- set default values
		delay = 30,
		quality = 1,
	}
	o.suppress = false
	--o.alpha = 112
	--o.alphatarget = 112
    return o
end


function AfGreedCheck:Init()
	local bHasConfigureFunction = true
	local strConfigureButtonText = "afGreedCheck"
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- AfGreedCheck OnLoad
-----------------------------------------------------------------------------------------------

function AfGreedCheck:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("AfGreedCheck.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	Apollo.LoadSprites("AfGreedCheckSprites.xml", "AfGreedCheckSprites")
end


-----------------------------------------------------------------------------------------------
-- AfGreedCheck OnDocLoaded
-----------------------------------------------------------------------------------------------

function AfGreedCheck:OnDocLoaded()
	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "AfGreedCheckForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- localize or not to uebersetzen, das ist hier die Frage...
		
		Apollo.RegisterSlashCommand("afgreed",          "OnAfGreedCheckOn",   self)

		Apollo.RegisterEventHandler("LootRollUpdate",   "OnLootRollUpdate",   self)
		
		Apollo.RegisterEventHandler("LootRollPassed",   "OnLootRollPassed",   self)
		Apollo.RegisterEventHandler("LootRollSelected", "OnLootRollSelected", self)
		Apollo.RegisterEventHandler("LootRollWon",      "OnLootRollWon",      self)
		
		Apollo.RegisterEventHandler("Group_Add",        "GroupChange",        self)
		Apollo.RegisterEventHandler("Group_Left",       "GroupChange",        self)
		Apollo.RegisterEventHandler("Group_Update",     "GroupChange",        self)
		Apollo.RegisterEventHandler("Group_Join",       "GroupChange",        self)
		Apollo.RegisterEventHandler("Group_Remove",     "GroupChange",        self)
		
		self.timer = ApolloTimer.Create(1.0, true, "OnTimer", self)
		self:GroupChange()
		--self.fadetimer = ApolloTimer.Create(0.1, true, "OnFadeTimer", self)
		--self.fadetimer:Stop()
	end
end


-----------------------------------------------------------------------------------------------
-- Save And Restore Settings
-----------------------------------------------------------------------------------------------

function AfGreedCheck:OnSave(eType)
	if eType == GameLib.CodeEnumAddonSaveLevel.Account then
		local tSavedData = {}
		tSavedData.Settings = self.Settings
		return tSavedData		
	end
	return
end


function AfGreedCheck:OnRestore(eType, tSavedData)
	if eType == GameLib.CodeEnumAddonSaveLevel.Account then
		if tSavedData.Settings ~= nil then
			-- replacing single values to not overwrite new default values by not existing values
			if tSavedData.Settings.delay ~= nil then self.Settings.delay = tSavedData.Settings.delay end
			if tSavedData.Settings.quality ~= nil then self.Settings.quality = tSavedData.Settings.quality end
		end
	end
end


-----------------------------------------------------------------------------------------------
-- Loot Caching
-----------------------------------------------------------------------------------------------

function AfGreedCheck:OnLootRollUpdate()
	local bChanged = false
	local tLoot = GameLib.GetLootRolls()
	for idx, RollItem in pairs(tLoot) do
		local LootItem = RollItem.itemDrop
		local iQuality = self:QualityToInt(LootItem:GetItemQuality())
		if iQuality >= self.Settings.quality then
			local bFound = false
			for idy, tEntry in pairs(self.LootCache) do
				if tEntry.uItem == LootItem then
					bFound = true
				end
			end
			if not bFound then
				bChanged = true
				self:AddNewItemToCache(LootItem)
				for idz, tDetails in pairs(RollItem) do
				end
			end
		end
	end
	if bChanged then
		self.suppress = false
		self:RefreshLoot()
	end
end


function AfGreedCheck:OnLootRollPassed(itemPassed, strPlayerName)
	for idx, tEntry in pairs(self.LootCache) do
		if tEntry.uItem == itemPassed then
			self.LootCache[idx].Choices[strPlayerName] = iPass
		end
	end
	self:RefreshLoot()
end


function AfGreedCheck:OnLootRollSelected(itemRolling, strPlayerName, bNeed)
	for idx, tEntry in pairs(self.LootCache) do
		if tEntry.uItem == itemRolling then
			local choice = iGreed
			if bNeed then
				choice = iNeed
			end
			self.LootCache[idx].Choices[strPlayerName] = choice
		end
	end
	self:RefreshLoot()
end


function AfGreedCheck:OnLootRollWon(itemWon, strWinnerName, bNeed)
	for idx, tEntry in pairs(self.LootCache) do
		if tEntry.uItem == itemWon then
			if bNeed then
				self.LootCache[idx].Choices[strWinnerName] = iWonNeed
			else
				self.LootCache[idx].Choices[strWinnerName] = iWonGreed
			end
			self.LootCache[idx].iCountDown = self.Settings.delay
		end
	end
	self:RefreshLoot()
end


function AfGreedCheck:AddNewItemToCache(LootItem)
	local tNewEntry = {
		uItem = LootItem,
		Choices = {},
		Possible = self.Group, -- who was able to chose
		iCountDown = 600,      -- failsafe: remove after 10 mins anyway
	}
	table.insert(self.LootCache, tNewEntry)
	tNewEntry = nil
end


-----------------------------------------------------------------------------------------------
-- AfGreedCheck Functions
-----------------------------------------------------------------------------------------------

function AfGreedCheck:OnAfGreedCheckOn(strCommand, strParam)
	self:LoadConfig()
end


function AfGreedCheck:OnConfigure()
	self:LoadConfig()
end


function AfGreedCheck:LoadConfig()
	if self.wndConfig == nil then
    	self.wndConfig = Apollo.LoadForm(self.xmlDoc, "Config", nil, self)
		self.wndConfig:FindChild("Version"):SetText(AfGreedVersion)
	end
	if self.wndConfig == nil then
		Apollo.AddAddonErrorText(self, "Could not load the config window for some reason.")
		return
	end
    self.wndConfig:Invoke()

	-- load settings into gui
	local wndSlider = self.wndConfig:FindChild("DelayTimer"):FindChild("SliderBar")
	wndSlider:SetValue(self.Settings.delay)
	self:OnChangeDelayTime(wndSlider, wndSlider, self.Settings.delay, 0)
	wndSlider = self.wndConfig:FindChild("QualitySlider"):FindChild("SliderBar")
	wndSlider:SetValue(self.Settings.quality)
	self:OnChangeItemQuality(wndSlider, wndSlider, self.Settings.quality, 0)
end


function AfGreedCheck:OnTimer()
	local bRemoved = false
	for idx, tEntry in pairs(self.LootCache) do
		if tEntry.iCountDown then
			tEntry.iCountDown = tEntry.iCountDown - 1
			if tEntry.iCountDown <= 0 then
				self.LootCache[idx] = nil
				bRemoved = true
			end
		end
	end
	if bRemoved then
		self:RefreshLoot()
	end
end


--function AfGreedCheck:OnFadeTimer()
--	if self.fade then
--		self.alpha = self.alpha + 2
--		if self.alpha > self.alphatarget then self.alpha = self.alphatarget end
--		local value = string.format("%02x",self.alpha)
--		self.wndMain:SetBGColor(value.."000000")
--		if self.alpha == self.alphatarget then
--			self.fadetimer:Stop()
--		end
--	else
--		self.alpha = self.alpha - 30
--		if self.alpha < 0 then self.alpha = 0 end
--		local value = string.format("%02x",self.alpha)
--		self.wndMain:SetBGColor(value.."000000")
--		if self.alpha == 0 then
--			self.fadetimer:Stop()
--		end
--	end
--end
	

function AfGreedCheck:log(strMeldung)
	if strMeldung == nil then strMeldung = "nil" end
	ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_System, strMeldung, "AfGreedCheck")
end


function AfGreedCheck:GroupChange()
	self:ClearNames()
	local tGroupSearch = {}
	self.Group = {}
	self.VirtualGroup = {}
	local j = GroupLib.GetMemberCount()
	self.GroupSize = j
	self.VirtualGroupSize = j
	for i=1,j,1 do
		local tMemberInfo = GroupLib.GetGroupMember(i)
		self:AddName(tMemberInfo.strCharacterName)
		self.Group[i] = tMemberInfo.strCharacterName
		self.VirtualGroup[i] = tMemberInfo.strCharacterName
		tGroupSearch[tMemberInfo.strCharacterName] = true
	end
	
	-- look into all "Possible"-values of cached loot:
	-- maybe a player who took a choice has left the group in the meantime:
	-- he should still be displayed until loot item times out
	for idx, tEntry in pairs(self.LootCache) do
		for _, sChar in pairs(tEntry.Possible) do
			if not tGroupSearch[sChar] then
				tGroupSearch[sChar] = true
				self.VirtualGroupSize = self.VirtualGroupSize + 1
				self.VirtualGroup[self.VirtualGroupSize] = sChar
				self:AddName(sChar)
			end
		end
	end
	
	local tOff = {self.wndMain:GetAnchorOffsets()}
	self.wndMain:SetAnchorOffsets(0-(225+(self.VirtualGroupSize*32)),tOff[2],tOff[3],tOff[4])
	self:RefreshLoot()
end


function AfGreedCheck:QualityToInt(iQuality)
	-- for correct sorting
	-- is this really neccessary? is it? IS IT?
	if iQuality == Item.CodeEnumItemQuality.Inferior  then return 1 end
	if iQuality == Item.CodeEnumItemQuality.Average   then return 2 end
	if iQuality == Item.CodeEnumItemQuality.Good      then return 3 end
	if iQuality == Item.CodeEnumItemQuality.Excellent then return 4 end
	if iQuality == Item.CodeEnumItemQuality.Superb    then return 5 end
	if iQuality == Item.CodeEnumItemQuality.Legendary then return 6 end
	if iQuality == Item.CodeEnumItemQuality.Artifact  then return 7 end
	return 0
end


-----------------------------------------------------------------------------------------------
-- AfGreedCheckForm Functions
-----------------------------------------------------------------------------------------------

function AfGreedCheck:ClearNames()
	local container = self.wndMain:FindChild("NameFrame")
	container:DestroyChildren()
end


function AfGreedCheck:AddName(sName)
	local container = self.wndMain:FindChild("NameFrame")
	local wndEntry = Apollo.LoadForm(self.xmlDoc, "NameEntry", container, self)
	local wndName = wndEntry:FindChild("Name")
	wndName:SetText(sName)
	container:ArrangeChildrenHorz()
end


function AfGreedCheck:RefreshLoot()
	local container = self.wndMain:FindChild("LootList")
	container:DestroyChildren()
	local nEntries = 0
	for idx, tEntry in pairs(self.LootCache) do
		self:AddLoot(tEntry.uItem)
		nEntries = nEntries + 1
	end
	local tOff = {self.wndMain:GetAnchorOffsets()}
	self.wndMain:SetAnchorOffsets(tOff[1],tOff[2],tOff[3],157+(nEntries*52))
	-- TODO: check for maximal size or try to find out about that maxresizing
	-- option or whatever it is called. where have i seen it?
	-- Well, the hell with that. Don't think somebody will really touch that limit.
	-- Hm, sure?
	-- SHUT UP AND STOP ARGUING WITH YOURSELF! stupid!
	-- k, but what about an option to place the window, like all 9 sides of a screen?
	-- sounds reasonable, put it on the far-distance-to-do-list.
	if nEntries == 0 then
		self.timer:Stop()
		self.suppress = false
		if self.wndMain:IsShown() then
			self.wndMain:Close()
		end
	else
		if not self.wndMain:IsShown() then
			if not self.suppress then
				self.wndMain:Invoke()
				self.timer:Start()
			end
		end
	end
end


function AfGreedCheck:AddLoot(uItem)
	local container = self.wndMain:FindChild("LootList")
	local wndEntry = Apollo.LoadForm(self.xmlDoc, "LootEntry", container, self)
	local iQuality = uItem:GetItemQuality()
	wndEntry:FindChild("ItemName"):SetText(uItem:GetName())
	wndEntry:FindChild("ItemName"):SetTextColor(ktEvalColors[iQuality])
	wndEntry:FindChild("ItemType"):SetText(uItem:GetItemTypeName())
	--wndEntry:FindChild("ItemType"):SetTextColor(ktEvalColors[iQuality])
	wndEntry:FindChild("ItemIcon"):SetSprite(uItem:GetIcon())
	wndEntry:FindChild("Quality"):SetSprite(ktEvalQualities[iQuality])

	local wndChoices = wndEntry:FindChild("Choices")
	local tGroupChoices = {}
	local tGroupPossible = {}
	for idx,tEntry in pairs(self.LootCache) do
		if tEntry.uItem == uItem then
			tGroupChoices = tEntry.Choices
			tGroupPossible = tEntry.Possible
		end
	end
	for iRun = 1,self.VirtualGroupSize,1 do
		local wndNewChoice = Apollo.LoadForm(self.xmlDoc, "ChoiceEntry", wndChoices, self)
		local wndNewChoiceChoice = wndNewChoice:FindChild("choice")
		
		-- has user been in group when loot dropped?
		local bWasPresent = false
		for _, strPossibleUser in pairs(tGroupPossible) do
			if strPossibleUser == self.VirtualGroup[iRun] then
				bWasPresent = true
			end
		end
		
		if bWasPresent then
			local iThisChoice = iEmpty
			if self.VirtualGroup[iRun] ~= nil then
				if tGroupChoices[self.VirtualGroup[iRun]] ~= nil then
					iThisChoice = tGroupChoices[self.VirtualGroup[iRun]]
				end
			end
			
			wndNewChoiceChoice:SetSprite(ksSprite[iThisChoice])
			if (iThisChoice == iWonNeed) or (iThisChoice == iWonGreed) then
				wndNewChoiceChoice:SetBGColor("red")
			end
		else -- user hasn't been in group when this dropped
			wndNewChoiceChoice:SetSprite("")
		end
	end
	wndChoices:ArrangeChildrenHorz()
	container:ArrangeChildrenVert()
end


function AfGreedCheck:OnCloseButton(wndHandler, wndControl, eMouseButton)
	self.suppress = true
	self.wndMain:Close()
end


--function AfGreedCheck:OnMouseEnter(wndHandler, wndControl, x, y)
--	self.fade = false
--	self.fadetimer:Start()
--end


--function AfGreedCheck:OnMouseExit(wndHandler, wndControl, x, y)
--	self.fade = true
--	self.fadetimer:Start()
--end


---------------------------------------------------------------------------------------------------
-- Config Functions
---------------------------------------------------------------------------------------------------

function AfGreedCheck:OnChangeDelayTime(wndHandler, wndControl, fNewValue, fOldValue)
	local iValue = math.floor(fNewValue)
	local sMessage = ""
	-- don't know what i was thinking of, gui limits min value to 10 or so, so
	-- these first to options should never trigger.
	-- ah, with "special function" i think i wanted the user to be able to
	-- dismiss each loot item manually. hm. will let it stay here as an option
	-- to think about.
	if iValue == -1 then
		sMessage = "special function"
	elseif iValue == 0 then
		sMessage = "remove at once"
	else
		local m = math.floor(iValue / 60)
		local s = math.floor(iValue - (m*60))
		sMessage = m..":";
		if s < 10 then
			sMessage = sMessage .. "0"
		end
		sMessage = sMessage .. s
	end
	wndControl:GetParent():GetParent():FindChild("Value"):SetText(sMessage)
	self.Settings.delay = iValue
end


function AfGreedCheck:OnChangeItemQuality(wndHandler, wndControl, fNewValue, fOldValue)
	local iValue = math.floor(fNewValue)
	local wndValue = wndControl:GetParent():GetParent():FindChild("Value")
	-- where do i get the (alredy localized) strings for that from?
	if iValue == 1 then
		wndValue:SetText("Inferior")
		wndValue:SetTextColor(ktEvalColors[Item.CodeEnumItemQuality.Inferior])
	elseif iValue == 2 then
		wndValue:SetText("Average")
		wndValue:SetTextColor(ktEvalColors[Item.CodeEnumItemQuality.Average])
	elseif iValue == 3 then
		wndValue:SetText("Good")
		wndValue:SetTextColor(ktEvalColors[Item.CodeEnumItemQuality.Good])
	elseif iValue == 4 then
		wndValue:SetText("Excellent")
		wndValue:SetTextColor(ktEvalColors[Item.CodeEnumItemQuality.Excellent])
	elseif iValue == 5 then
		wndValue:SetText("Superb")
		wndValue:SetTextColor(ktEvalColors[Item.CodeEnumItemQuality.Superb])
	elseif iValue == 6 then
		wndValue:SetText("Legendary")
		wndValue:SetTextColor(ktEvalColors[Item.CodeEnumItemQuality.Legendary])
	elseif iValue == 7 then
		wndValue:SetText("Artifact")
		wndValue:SetTextColor(ktEvalColors[Item.CodeEnumItemQuality.Artifact])
	end
	self.Settings.quality = iValue
end


function AfGreedCheck:OnConfigOK(wndHandler, wndControl, eMouseButton)
	self.wndConfig:Close()
end


-----------------------------------------------------------------------------------------------
-- AfGreedCheck Instance
-----------------------------------------------------------------------------------------------
local AfGreedCheckInst = AfGreedCheck:new()
AfGreedCheckInst:Init()
