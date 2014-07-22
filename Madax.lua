local LoginFrame = CreateFrame("Frame")
LoginFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
LoginFrame:SetScript("OnEvent",function()
	LoginFrame:SetScript("OnEvent",nil);
	
	print("Madax: Welcome "..UnitName("player").."!");
	
	Madax = {};

	if not MadaxSavedVars then
		MadaxSavedVars = {}
	end;
	
	Madax.itemList = MadaxSavedVars;
	
	--check whether guild bank is open or closed
	Madax.guildBankOpen = (GuildBankFrame~=nil);
	Madax.GuildBankOpenFrame = CreateFrame("Frame");
	Madax.GuildBankOpenFrame:RegisterEvent("GUILDBANKFRAME_OPENED");
	Madax.GuildBankOpenFrame:RegisterEvent("GUILDBANKFRAME_CLOSED");
	Madax.GuildBankOpenFrame:SetScript("OnEvent",function(self,event)
		Madax.guildBankOpen = (event == "GUILDBANKFRAME_OPENED");
	end);

	--when tab is changed: show item list for that tab
	Madax.GuildBankSlotsChanged = CreateFrame("Frame");
	Madax.GuildBankSlotsChanged:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED");
	Madax.GuildBankSlotsChanged:SetScript("OnEvent",function(self)
		if not Madax.Coroutine then
			Madax.UpdateItemListFrame();
		end;
	end);

	--change current guild bank tab to requested
	function Madax.SetGuildBankTab(i,query)
		if not Madax.guildBankOpen then
			return;
		end;
		
		if i > GetNumGuildBankTabs() then
			print("Madax: Requested guild bank tab which is not yet unlocked ("..i..").");
			return;
		end;
		
		if GetCurrentGuildBankTab() ~= i then
			SetCurrentGuildBankTab(i);
		end;
		
		if query then
			QueryGuildBankTab(i);
		end;
	end;

	Madax.FreeSlotsTimer = CreateFrame("Frame");
	Madax.FreeSlotsTimer.MaxTime = .2;--seconds
	function Madax.FreeSlotsTimer.OnUpdate(self,elapsed)
		Madax.FreeSlotsTimer.Timer = Madax.FreeSlotsTimer.Timer + elapsed;
		
		if Madax.FreeSlotsTimer.Timer > Madax.FreeSlotsTimer.MaxTime then
			self:SetScript("OnUpdate",nil);
			coroutine.resume(Madax.FreeSlotsCoroutine);
		end;
	end;
	
	function Madax.GetFreeSlotsInGuildBankPerTab()
		Madax.FreeSlotsInVault = {};
		
		for tab = 1, GetNumGuildBankTabs() do
			Madax.FreeSlotsInVault[tab] = 0;
			QueryGuildBankTab(tab);
			
			Madax.FreeSlotsTimer.Timer = 0;
			Madax.FreeSlotsTimer:SetScript("OnUpdate",Madax.FreeSlotsTimer.OnUpdate);
			coroutine.yield();--wait for tab data
			
			for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
				if not GetGuildBankItemInfo(tab,slot) then
					Madax.FreeSlotsInVault[tab] = Madax.FreeSlotsInVault[tab] + 1;
				end;
			end;
		end;
		
		Madax.FreeSlotsCoroutine = nil;
	end;
	
	function Madax.MoveItem(source_bagID,source_slot,target_bagID,target_slot)
		if not Madax.guildBankOpen then
			return;
		end;
		
		if (not target_slot) then--item from backpack to guild bank
			--check if source item exists and we can move it
			local texture, _, itemLocked = GetContainerItemInfo(source_bagID,source_slot);
			
			if (not texture) or itemLocked then
				print("Madax: No/locked item found on requested location ("..source_bagID..","..source_slot.." - "..itemLocked..").");
				return;
			end;
			
			Madax.SetGuildBankTab(target_bagID);
			UseContainerItem(source_bagID,source_slot);
		else--item from guild bank to backpack
			Madax.SetGuildBankTab(source_bagID);
			
			local texture, _, itemLocked = GetGuildBankItemInfo(source_bagID,source_slot);
			
			if (not texture) or itemLocked then
				print("Madax: No/locked item found on requested location ("..source_bagID..","..source_slot.." - "..itemLocked..").");
				return;
			end;
			
			AutoStoreGuildBankItem(source_bagID,source_slot);
		end;
	end;

	function Madax.MoveAllItemsToGuildBank_Yield()
		Madax.CoroutineResumeFrame.OnUpdateTimer = 0;
		Madax.CoroutineResumeFrame:SetScript("OnUpdate",Madax.CoroutineResumeFrame.OnUpdate);
		coroutine.yield();
		Madax.numMovingItems = 0;
	end;
	
	--move all items in the itemList to the guildbank. if i is specified: only items assigend to the i'th tab will be moved. if i is >not< specified: move items for all tabs
	function Madax.MoveAllItemsToGuildBank(i)
		local openedTab = i or GetCurrentGuildBankTab();
		local moveCount = 0;
		Madax.numMovingItems = 0;
		
		for run = 1,2 do
			if run == 1 then
				Madax.FreeSlotsCoroutine = coroutine.create(function()
					Madax.GetFreeSlotsInGuildBankPerTab();
					coroutine.resume( Madax.Coroutine );
				end);
				
				coroutine.resume( Madax.FreeSlotsCoroutine );
				coroutine.yield();
			else
				Madax.MoveAllItemsToGuildBank_Yield();
			end;
			
			for bagID = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
				for slot = 1, GetContainerNumSlots(bagID) do
					local itemID = GetContainerItemID(bagID,slot);
					
					if itemID and Madax.itemList[itemID] then
						local movedTab;
						
						if i and Madax.itemList[itemID][i] and ( Madax.FreeSlotsInVault[i]>0 ) then
							movedTab = i;
							Madax.MoveItem(bagID,slot,i);
						elseif (not i) then
							for minTab = 1, GetNumGuildBankTabs() do
								if (not movedTab) and Madax.itemList[itemID][minTab] and ( Madax.FreeSlotsInVault[minTab]>0 )then
									movedTab = minTab;
									Madax.MoveItem(bagID,slot,minTab);
								end;
							end;
						end;
						
						if movedTab then
							moveCount = moveCount + 1;
							Madax.numMovingItems = Madax.numMovingItems + 1;
							Madax.FreeSlotsInVault[movedTab] = Madax.FreeSlotsInVault[movedTab] - 1;
						end;
						
						if Madax.numMovingItems >= Madax.maxMovingItems then
							Madax.MoveAllItemsToGuildBank_Yield();
						end;
					end;
				end;
			end;
		end;
		
		Madax.SetGuildBankTab(openedTab,true);
		
		Madax.Coroutine = nil;
		
		print("Madax: Finished moving "..moveCount.." stacks.");
		
		Madax.DepositAllButton:Enable();
		Madax.DepositThisButton:Enable();
		Madax.AddAllToList:Enable();
	end;

	--change the following two variables for adjustments to speed of placing items to guildbank:
	Madax.maxMovingItems = 3;
	Madax.MaxOnUpdateTimer = 1.3;--seconds
	Madax.CoroutineResumeFrame = CreateFrame("Frame");

	--timer for resuming
	function Madax.CoroutineResumeFrame.OnUpdate(self,elapsed)
		Madax.CoroutineResumeFrame.OnUpdateTimer = Madax.CoroutineResumeFrame.OnUpdateTimer + elapsed;
		
		if Madax.CoroutineResumeFrame.OnUpdateTimer >= Madax.MaxOnUpdateTimer then
			Madax.CoroutineResumeFrame:SetScript("OnUpdate",nil);
			coroutine.resume( Madax.Coroutine );
		end;
	end;

	--returns (sorted) table with all items for a specific (guildbank) tab (the return value is a table containing subtables with item names [1], links [2] and IDs [3])
	function Madax.GetItemTableForTab(i)
		local sortedTable_itemNameLinkID = {};
		local unsortedTable_itemID = {};
		
		for itemID, tabs in pairs(Madax.itemList) do
			if tabs[i] then
				unsortedTable_itemID[itemID] = true;
			end;
		end;
		
		local index = 0;
		for itemID in pairs(unsortedTable_itemID) do
			index = index + 1;
			local itemName, itemLink = GetItemInfo(itemID);
			tinsert(sortedTable_itemNameLinkID,{itemName,itemLink,itemID});
		end;
		
		sort(sortedTable_itemNameLinkID,function(a,b)
			return a[1] < b[1];
		end);
		
		return sortedTable_itemNameLinkID;
	end;

	Madax.ItemLines = {};
	Madax.LineOffset = 15;
	Madax.NumItemLines = 0;

	--returns (a new or a reused one) line to display our item link
	function Madax.GetItemLine(i)
		if Madax.ItemLines[i] then
			Madax.ItemLines[i]:Show();
		else
			Madax.ItemLines[i] = CreateFrame("Frame",nil,Madax.itemListFrame);
			Madax.ItemLines[i]:SetWidth(Madax.itemListFrame:GetWidth()*0.95);
			Madax.ItemLines[i]:SetHeight(20);
			
			Madax.ItemLines[i]:SetScript("OnLeave",function()
				GameTooltip:Hide();
			end);
			
			Madax.ItemLines[i].text = Madax.ItemLines[i]:CreateFontString(nil,"ARTWORK","GameFontNormal");
			Madax.ItemLines[i].text:SetAllPoints(Madax.ItemLines[i]);
			
			Madax.NumItemLines = Madax.NumItemLines + 1;
		end;
		
		Madax.ItemLines[i]:ClearAllPoints();
		Madax.ItemLines[i]:SetPoint("TOPLEFT",Madax.itemListFrame,"TOPLEFT",5,-Madax.LineOffset*i);
		
		return Madax.ItemLines[i];
	end;

	function Madax.UpdateItemListFrame()
		local tab = GetCurrentGuildBankTab();
		local requestedItemCount = 0;
		for _, itemNameLinkID in ipairs(Madax.GetItemTableForTab(tab)) do--itemNameLinkID - 1: name 2: link 3: id
			requestedItemCount = requestedItemCount + 1;
			
			local line = Madax.GetItemLine(requestedItemCount)
			
			line:SetScript("OnEnter",function()
				GameTooltip:SetOwner(line,"ANCHOR_TOPLEFT",0,2);
				GameTooltip:SetItemByID(itemNameLinkID[3]);
				GameTooltip:Show();
			end);
			
			line:SetScript("OnMouseUp",function(self,button)
				if button == "LeftButton" then
					Madax.itemListFrame.OnMouseUp(self,button);
				elseif button == "RightButton" and (not GetCursorInfo()) then
					Madax.itemList[itemNameLinkID[3]][tab] = nil;
					
					local noEntry = true;
					
					for tabEntry in pairs(Madax.itemList[itemNameLinkID[3]]) do
						noEntry = false;
					end;
					
					--clean up
					if noEntry then
						Madax.itemList[itemNameLinkID[3]] = nil;
					end;
					
					Madax.UpdateItemListFrame();
				end;
			end);
			
			line.text:SetText(itemNameLinkID[2]);
		end;

		--hide all unused lines
		for i = requestedItemCount + 1, Madax.NumItemLines do
			if i > 1 then
				Madax.ItemLines[i]:Hide();
			end;
		end;	
		
		if requestedItemCount == 0 then
			local line = Madax.GetItemLine(1);
			line:SetScript("OnEnter",nil);
			line:SetScript("OnMouseDown",function(self,button)
				if button == "LeftButton" then
					Madax.itemListFrame.OnMouseUp(self,button);
				end;
			end);
			line.text:SetText("tab list empty");
			requestedItemCount = 1;
		end;
		
		--adjust container frame height
		Madax.itemListFrame:SetHeight( (2+requestedItemCount)*15 + 22 );
	end;

	function Madax.CreateWindows()
		local parentFrame = GuildBankFrame;

		if ArkInventory then
			local id = ArkInventory.Const.Location.Vault;
			parentFrame = _G["ARKINV_Frame"..id];
		end;
		
		Madax.itemListFrame = CreateFrame("Frame",nil,parentFrame);
		local listFrame = Madax.itemListFrame;

		listFrame:SetSize(160,100);
		listFrame:SetPoint("TOPLEFT",parentFrame,"TOPRIGHT",20,0);

		listFrame:SetBackdrop({	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
								edgeFile = "Interface/ArenaEnemyFrame/UI-Arena-Border",
								edgeSize = 2});
								
		listFrame.OnMouseUp = function(self,button)
			local cursorType, itemID = GetCursorInfo();
			if button == "LeftButton" and (cursorType == "item") then
				local tabTable = Madax.itemList[itemID] or {};
				tabTable[GetCurrentGuildBankTab()] = true;
				Madax.itemList[itemID] = tabTable;
				
				Madax.UpdateItemListFrame();
				
				ClearCursor();
			end;
		end;
		
		listFrame:SetScript("OnMouseUp",function(self,button)
			self.OnMouseUp(self,button);
		end);
		
		local function AddTooltip(self,text,noBottom)
			self:SetScript("OnEnter",function()
				if noBottom then
					GameTooltip:SetOwner(self,"ANCHOR_TOPRIGHT",2,0);
				else
					GameTooltip:SetOwner(self,"ANCHOR_BOTTOM",0,-2);
				end;
				GameTooltip:SetText(text);
				GameTooltip:Show();
			end);

			self:SetScript("OnLeave",function()
				GameTooltip:Hide();
			end);
		end;
		
		Madax.DepositAllButton = CreateFrame("Button",nil,listFrame,"UIPanelButtonTemplate");
		Madax.DepositAllButton:SetSize(40,20);
		Madax.DepositAllButton:SetPoint("BOTTOMLEFT",30,5);
		Madax.DepositAllButton:SetText("all");
		AddTooltip(Madax.DepositAllButton,"Dump items to all tabs");
		Madax.DepositAllButton:SetScript("OnClick",function()
			if Madax.Coroutine then
				return;
			end;
			
			Madax.DepositAllButton:Disable();
			Madax.DepositThisButton:Disable();
			Madax.AddAllToList:Disable();
			
			Madax.Coroutine = coroutine.create( function()
				Madax.MoveAllItemsToGuildBank();
			end );
			
			coroutine.resume( Madax.Coroutine );
		end);
		
		Madax.DepositThisButton = CreateFrame("Button",nil,listFrame,"UIPanelButtonTemplate");
		Madax.DepositThisButton:SetSize(40,20);
		Madax.DepositThisButton:SetPoint("BOTTOMRIGHT",-30,5);
		Madax.DepositThisButton:SetText("this");
		AddTooltip(Madax.DepositThisButton,"Dump items to this tab");
		Madax.DepositThisButton:SetScript("OnClick",function()
			if Madax.Coroutine then
				return;
			end;
			
			Madax.DepositAllButton:Disable();
			Madax.DepositThisButton:Disable();
			Madax.AddAllToList:Disable();
			
			Madax.Coroutine = coroutine.create( function()
				Madax.MoveAllItemsToGuildBank(GetCurrentGuildBankTab());
			end );
			
			coroutine.resume( Madax.Coroutine );
		end);
		
		Madax.AddAllToList = CreateFrame("Button",nil,listFrame,"UIPanelButtonTemplate");
		Madax.AddAllToList:SetSize(20,20);
		Madax.AddAllToList:SetPoint("TOPRIGHT",-5,-5);
		Madax.AddAllToList:SetText("+");
		AddTooltip(Madax.AddAllToList,"Add all items to list",true);
		Madax.AddAllToList:SetScript("OnClick",function()
			local tab = GetCurrentGuildBankTab();
			
			for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
				local itemID = (strmatch(GetGuildBankItemLink(tab,slot) or "","Hitem%:%d+%:") or ""):match("%d+");
				
				if itemID then
					itemID = tonumber(itemID);
					local tabTable = Madax.itemList[itemID] or {};
					tabTable[tab] = true;
					Madax.itemList[itemID] = tabTable;
				end;
			end;
			
			Madax.UpdateItemListFrame();
			
			print("Madax: Added all items from this tab to the list.");
		end);
	end;

	Madax.CreateWindows();
end);