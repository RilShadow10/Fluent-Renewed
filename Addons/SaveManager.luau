local httpService = game:GetService("HttpService")

type Dropdown = {Value: any, Values: {i: any}, Multi: boolean, Displayer: (v) -> (n)?, SetValue: (any) -> ()}

local DisplayerParser = {
	Encode = function(Value)
		local Encoded = {}

		for Val: any, Bool: boolean in Value do
			table.insert(Encoded, Val)
		end

		return Encoded
	end,
}

local function TableEqual(Table, Reflect)
	for Index, Value in Table do 
		if Reflect[Index] ~= Value then return false end 
	end 

	return true
end  

local function SetDisplayerDropdownValue(Dropdown: Dropdown, Value)
	if Dropdown.Multi then
		local Values = {}
		
		for _, DataValue in Value do 
			for _, DropdownValue in Dropdown.Values do 
				if typeof(DropdownValue) ~= 'table' or not TableEqual(DataValue, DropdownValue) then continue end 
				
				Values[DropdownValue] = true
				break
			end
		end
		
		Dropdown:SetValue(Values)
	else
		for _, DropdownValue in Dropdown.Values do 
			if typeof(DropdownValue) ~= 'table' or not TableEqual(Value, DropdownValue) then continue end 
			
			Dropdown:SetValue(DropdownValue)
			break
		end	
	end
end

local SaveManager = {} do
	SaveManager.Folder = "FluentSettings"
	SaveManager.Ignore = {}
	SaveManager.Options, SaveManager.Library = {}, {}
	SaveManager.AutoSaveEnabled = false
	SaveManager.AutoSaveConfigName = "autosave"
	SaveManager.LastSave = 0
	SaveManager.HookedElements = {} -- Track hooked elements to avoid duplicates
	SaveManager.ElementFirstChange = {}
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object) 
				return { type = "Toggle", idx = idx, value = object.Value, Timestamp = object.Instance.CreatedAt } 
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Slider = {
			Save = function(idx, object)
				return { type = "Slider", idx = idx, value = object.Value, Timestamp = object.Instance.CreatedAt }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Dropdown = {
			Save = function(idx, object)
				local HasDisplayer = object.CustomDisplayer
				
				return { type = "Dropdown", idx = idx, value = (HasDisplayer and object.Multi and DisplayerParser.Encode(object.Value) or object.Value), mutli = object.Multi, Timestamp = object.Instance.CreatedAt, displayer = HasDisplayer}
			end,
			Load = function(idx, data)
				if data.value == nil then return end
				
				local DropdownElement = SaveManager.Options[idx]
				if not DropdownElement then return end
				
				local Value = data.value 
				if typeof(Value) ~= 'table' or (not data.displayer) then
					DropdownElement:SetValue(Value)
					return
				end
				
				SetDisplayerDropdownValue(DropdownElement, Value)
			end,
		},
		Colorpicker = {
			Save = function(idx, object)
				return { type = "Colorpicker", idx = idx, value = object.Value:ToHex(), transparency = object.Transparency, Timestamp = object.Instance.CreatedAt }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency)
				end
			end,
		},
		Keybind = {
			Save = function(idx, object)
				return { type = "Keybind", idx = idx, mode = object.Mode, key = object.Value, Timestamp = object.Instance.CreatedAt }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then 
					SaveManager.Options[idx]:SetValue(data.key, data.mode)
				end
			end,
		},
		Input = {
			Save = function(idx, object)
				return { type = "Input", idx = idx, text = object.Value, Timestamp = object.Instance.CreatedAt }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] and type(data.text) == "string" then
					SaveManager.Options[idx]:SetValue(data.text)
				end
			end,
		},
	}

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.Folder = folder
		self:BuildFolderTree()
	end

	function SaveManager:Save(name): (boolean, string?)
		if (not name) then
			return false, "No config file is selected"
		end

		local fullPath = `{self.Folder}/settings/{name}.json`

		local data = {
			objects = {}
		}

		for idx, option in next, SaveManager.Options do
			if not self.Parser[option.Type] then continue end
			if self.Ignore[idx] then continue end

			data.objects[#data.objects + 1] = self.Parser[option.Type].Save(idx, option)
		end

		table.sort(data.objects, function(v1: { Timestamp: number }, v2: { Timestamp: number })
			return v1.Timestamp < v2.Timestamp
		end)

		local success, encoded = pcall(httpService.JSONEncode, httpService, data)
		if not success then
			return false, "Failed to JSON-Encode data: " .. tostring(encoded)
		end

		local success, err = pcall(writefile, fullPath, encoded)
		if not success then
			return false, "Failed to write file: " .. (err or "unknown error")
		end
		print("Saved to:", fullPath)
		return true
	end

	function SaveManager:Load(name): (boolean, string?)
		if (not name) then
			return false, "No config file is selected"
		end

		local file = `{self.Folder}/settings/{name}.json`
		if not isfile(file) then return false, "invalid file" end

		local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
		if not success then return false, "decode error: " .. tostring(decoded) end

		for _, option in next, decoded.objects do
			if self.Parser[option.type] then
				task.spawn(self.Library.SafeCallback, self.Library, self.Parser[option.type].Load, option.idx, option)
			end
		end

		self.Library:SetTheme(self.Library.Theme)

		return true
	end

	function SaveManager:IgnoreThemeSettings()
		self:SetIgnoreIndexes({ 
			"InterfaceManager_InterfaceTheme", "InterfaceManager_AcrylicToggle", "InterfaceManager_TransparentToggle", "InterfaceManager_MenuKeybind"
		})
	end

	function SaveManager:BuildFolderTree()
		local paths = {
			self.Folder,
			`{self.Folder}/settings`
		}

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
				print("Created folder:", str)
			end
		end
	end

	function SaveManager:RefreshConfigList()
		local list = listfiles(`{self.Folder}/settings`) or {}

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == ".json" then
				local pos = file:find(".json", 1, true)
				local start = pos

				if typeof(pos) == "number" and typeof(start) == "number" then
					local char = file:sub(pos, pos)
					while char ~= "/" and char ~= "\\" and char ~= "" do
						pos = pos - 1
						char = file:sub(pos, pos)
					end

					if char == "/" or char == "\\" then
						local name = file:sub(pos + 1, start - 1)
						if name ~= "options" then
							out[#out + 1] = name
						end
					end
				end
			end
		end

		return out
	end

	function SaveManager:SetLibrary(library)
		self.Library = library
		self.Options = library.Options
		self:WrapUIElements()
	end

	function SaveManager:LoadAutoloadConfig()
		if isfile(`{self.Folder}/settings/autoload.txt`) then
			local name = readfile(`{self.Folder}/settings/autoload.txt`)

			local success, err = self:Load(name)
			if not success then
				return self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = `Failed to load autoload config: {err}`,
					Duration = 7
				})
			end

			return self.Library:Notify({
				Title = "Interface",
				Content = "Config loader",
				SubContent = string.format("Auto loaded config %q", name),
				Duration = 7
			})
		end

		return nil
	end

	function SaveManager:LoadAutoSaveConfig()
		local file = `{self.Folder}/settings/{self.AutoSaveConfigName}.json`
		if isfile(file) then
			local success, err = self:Load(self.AutoSaveConfigName)
			if not success then
				self.Library:Notify({
					Title = "Interface",
					Content = "Autosave",
					SubContent = `Failed to load autosaved config: {err}`,
					Duration = 7
				})
			else
				self.Library:Notify({
					Title = "Interface",
					Content = "Autosave",
					SubContent = "Loaded autosaved settings",
					Duration = 3
				})
			end
		end
	end

	function SaveManager:AutoSave()
		local success, err = self:Save(self.AutoSaveConfigName)
	end

	function SaveManager:WrapUIElements()
		-- Function to hook OnChanged for a single element
		local function HookElement(id, element)
			if SaveManager.HookedElements[id] then
				return -- Already hooked
			end
			if element.OnChanged then
				SaveManager.HookedElements[id] = true
				SaveManager.ElementFirstChange[id] = true
				element:OnChanged(function(value)
					if SaveManager.ElementFirstChange[id] then
						SaveManager.ElementFirstChange[id] = false
						print("Ignored initial OnChanged for:", id, "Type:", element.Type, "Value:", tostring(value or element.Value))
						return
					end
					-- Use 'value' for Toggle/Slider/Dropdown, element.Value for others
					local displayValue = value or element.Value
					SaveManager:AutoSave()
				end)
			end
		end

		-- Initial hook for existing elements
		for id, element in self.Options do
			HookElement(id, element)
		end

		-- Monitor for new elements (polling approach)
		--[[
		task.spawn(function()
			local lastCount = 0
			while true do
				local currentCount = 0
				for id, element in self.Options do
					currentCount += 1
					if not SaveManager.HookedElements[id] then
						HookElement(id, element)
					end
				end
				if currentCount ~= lastCount then
					print("Detected", currentCount, "elements in Library.Options")
					lastCount = currentCount
				end
				task.wait(0.1) -- Poll every 0.1 seconds
			end
		end)
		]]
		SaveManager:AutoSave()
	end

	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, "Must set SaveManager.Library")

		local section = tab:AddSection("Configuration")

		section:AddInput("SaveManager_ConfigName", { Title = "Config name" })
		section:AddDropdown("SaveManager_ConfigList", { Title = "Config list", Values = self:RefreshConfigList(), AllowNull = true })

		section:AddToggle("SaveManager_AutoSaveToggle", {
			Title = "Enable Autosave",
			Description = "Automatically save settings when changed",
			Default = false,
			Callback = function(value)
				self.AutoSaveEnabled = value
				SaveManager:AutoSave()
			end
		})

		section:AddButton({
			Title = "Create config",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigName.Value

				if name:gsub(" ", "") == "" then 
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Invalid config name (empty)",
						Duration = 7
					})
				end

				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to save config: " .. err,
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Created config %q", name),
					Duration = 7
				})

				SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
				SaveManager.Options.SaveManager_ConfigList:SetValue(nil)

				return nil
			end
		})

		section:AddButton({Title = "Load config", Callback = function()
			local name = SaveManager.Options.SaveManager_ConfigList.Value

			local success, err = self:Load(name)
			if not success then
				return self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "Failed to load config: " .. err,
					Duration = 7
				})
			end

			return self.Library:Notify({
				Title = "Interface",
				Content = "Config loader",
				SubContent = string.format("Loaded config %q", name),
				Duration = 7
			})
		end})

		section:AddButton({Title = "Overwrite config", Callback = function()
			local name = SaveManager.Options.SaveManager_ConfigList.Value

			local success, err = self:Save(name)
			if not success then
				return self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "Failed to overwrite config: " .. err,
					Duration = 7
				})
			end

			return self.Library:Notify({
				Title = "Interface",
				Content = "Config loader",
				SubContent = string.format("Overwrote config %q", name),
				Duration = 7
			})
		end})

		section:AddButton({Title = "Refresh list", Callback = function()
			SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
			SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
		end})

		local AutoloadButton
		AutoloadButton = section:AddButton({Title = "Set as autoload", Description = "Current autoload config: none", Callback = function()
			local name = SaveManager.Options.SaveManager_ConfigList.Value
			local success, err = pcall(writefile, `{self.Folder}/settings/autoload.txt`, name)
			if not success then
				return self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "Failed to set autoload: " .. (err or "unknown error"),
					Duration = 7
				})
			end
			AutoloadButton:SetDesc("Current autoload config: " .. name)
			self.Library:Notify({
				Title = "Interface",
				Content = "Config loader",
				SubContent = string.format("Set %q to auto load", name),
				Duration = 7
			})
		end})

		local RemoveAutoloadButton
		RemoveAutoloadButton = section:AddButton({Title = "Remove autoload", Callback = function()
			delfile(`{self.Folder}/settings/autoload.txt`)
			AutoloadButton:SetDesc("Current autoload config:")
			self.Library:Notify({
				Title = "Interface",
				Content = "Config loader",
				SubContent = string.format("Removed auto load"),
				Duration = 4
			})
		end})

		if isfile(`{self.Folder}/settings/autoload.txt`) then
			local name = readfile(`{self.Folder}/settings/autoload.txt`)
			AutoloadButton:SetDesc("Current autoload config: " .. name)
		end

		SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName", "SaveManager_AutoSaveToggle" })

		-- Load autosaved config on script execution
		self:LoadAutoSaveConfig()
	end

	SaveManager:BuildFolderTree()
end

return SaveManager
