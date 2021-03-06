--[[
	Shine ban system.
]]

local Shine = Shine
local Hook = Shine.Hook

local IsType = Shine.IsType

local Plugin = Plugin
Plugin.Version = "1.5"

local Notify = Shared.Message
local Clamp = math.Clamp
local Encode, Decode = json.encode, json.decode
local Max = math.max
local pairs = pairs
local StringFind = string.find
local StringFormat = string.format
local TableConcat = table.concat
local TableCopy = table.Copy
local TableRemove = table.remove
local TableShallowMerge = table.ShallowMerge
local TableSort = table.sort
local Time = os.time

Plugin.HasConfig = true
Plugin.ConfigName = "Bans.json"
Plugin.PrintName = "Bans"

Plugin.VanillaConfig = "config://BannedPlayers.json" --Auto-convert the old ban file if it's found.

--Max number of ban entries to network in one go.
Plugin.MAX_BAN_PER_NETMESSAGE = 10
--Permission required to receive the ban list.
Plugin.ListPermission = "sh_unban"

local Hooked

Plugin.DefaultConfig = {
	Banned = {},
	DefaultBanTime = 60, --Default of 1 hour ban if a time is not given.
	GetBansFromWeb = false,
	GetBansWithPOST = false, --Should we use POST with extra keys to get bans?
	BansURL = "",
	BansSubmitURL = "",
	BansSubmitArguments = {},
	MaxSubmitRetries = 3,
	SubmitTimeout = 5,
	VanillaConfigUpToDate = false,
	CheckFamilySharing = false,
	BanSharerOnSharedBan = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true
Plugin.SilentConfigSave = true

--[[
	Called on plugin startup, we create the chat commands and set ourself to enabled.
	We return true to indicate a successful startup.
]]
function Plugin:Initialise()
	self:BroadcastModuleEvent( "Initialise" )
	self.Retries = {}

	if self.Config.GetBansFromWeb then
		--Load bans list after everything else.
		self:SimpleTimer( 1, function()
			self:LoadBansFromWeb()
		end )
	else
		self:MergeNS2IntoShine()
	end

	self:CreateCommands()
	self:CheckBans()

	if not Hooked then
		--Hook into the default banning commands.
		Event.Hook( "Console_sv_ban", function( Client, ... )
			Shine:RunCommand( Client, "sh_ban", false, ... )
		end )

		Event.Hook( "Console_sv_unban", function( Client, ... )
			Shine:RunCommand( Client, "sh_unban", false, ... )
		end )

		--Override the bans list function (have to do it after everything's loaded).
		self:SimpleTimer( 1, function()
			function GetBannedPlayersList()
				local Bans = self.Config.Banned
				local Ret = {}

				local Count = 1

				for ID, Data in pairs( Bans ) do
					Ret[ Count ] = { name = Data.Name, id = ID, reason = Data.Reason,
						time = Data.UnbanTime }

					Count = Count + 1
				end

				return Ret
			end
		end )

		Hooked = true
	end

	self:VerifyConfig()

	self.Enabled = true

	return true
end

function Plugin:VerifyConfig()
	self.Config.MaxSubmitRetries = Max( self.Config.MaxSubmitRetries, 0 )
	self.Config.SubmitTimeout = Max( self.Config.SubmitTimeout, 0 )
	self.Config.DefaultBanTime = Max( self.Config.DefaultBanTime, 0 )
end

function Plugin:LoadBansFromWeb()
	local function BansResponse( Response )
		if not Response then
			self.Logger:Error( "Loading bans from the web failed. Check the config to make sure the URL is correct." )
			return
		end

		local BansData, Pos, Err = Decode( Response )
		if not IsType( BansData, "table" ) then
			self.Logger:Error( "Loading bans from the web received invalid JSON. Error: %s.",
				Err )
			self.Logger:Debug( "Response content:\n%s", Response )
			return
		end

		local Edited
		if BansData.Banned then
			Edited = true
			self.Config.Banned = BansData.Banned
		elseif BansData[ 1 ] and BanData[ 1 ].id then
			Edited = true
			self.Config.Banned = self:NS2ToShine( BansData )
		end

		-- Cache the data in case we get a bad response later.
		if Edited and not self:CheckBans() then
			self:SaveConfig()
		end
		self:GenerateNetworkData()

		self.Logger:Info( "Loaded bans from web successfully." )
	end

	local Callbacks = {
		OnSuccess = BansResponse,
		OnFailure = function()
			self.Logger:Error( "No response from server when attempting to load bans." )
		end
	}

	self.Logger:Debug( "Retrieving bans from: %s", self.Config.BansURL )

	if self.Config.GetBansWithPOST then
		Shine.HTTPRequestWithRetry( self.Config.BansURL, "POST", self.Config.BansSubmitArguments,
			Callbacks, self.Config.MaxSubmitRetries, self.Config.SubmitTimeout )
	else
		Shine.HTTPRequestWithRetry( self.Config.BansURL, "GET", Callbacks,
			self.Config.MaxSubmitRetries, self.Config.SubmitTimeout )
	end
end

function Plugin:SaveConfig()
	self:ShineToNS2()

	self.BaseClass.SaveConfig( self )
end

--[[
	If our config is being web loaded, we'll need to retrieve web bans separately.
]]
function Plugin:OnWebConfigLoaded()
	if self.Config.GetBansFromWeb then
		self:LoadBansFromWeb()
	end

	self:VerifyConfig()
end

local function NS2EntryToShineEntry( Table )
	local Duration = Table.duration
		or ( Table.time > 0 and Table.time - Time() or 0 )

	return {
		Name = Table.name,
		UnbanTime = Table.time,
		Reason = Table.reason,
		BannedBy = Table.bannedby or "<unknown>",
		BannerID = Table.bannerid or 0,
		Duration = Duration
	}
end

--[[
	Merges the NS2/Dak config into the Shine config.
]]
function Plugin:MergeNS2IntoShine()
	local Edited

	local VanillaBans = Shine.LoadJSONFile( self.VanillaConfig )
	local MergedTable = self.Config.Banned
	local VanillaIDs = {}

	if IsType( VanillaBans, "table" ) then
		for i = 1, #VanillaBans do
			local Table = VanillaBans[ i ]
			local ID = tostring( Table.id )

			if ID then
				VanillaIDs[ ID ] = true

				if not MergedTable[ ID ] or ( MergedTable[ ID ]
				and MergedTable[ ID ].UnbanTime ~= Table.time ) then
					MergedTable[ ID ] = NS2EntryToShineEntry( Table )

					Edited = true
				end
			end
		end
	end

	if self.Config.VanillaConfigUpToDate then
		for ID in pairs( MergedTable ) do
			if not VanillaIDs[ ID ] then
				MergedTable[ ID ] = nil
				Edited = true
			end
		end
	else
		Edited = true
		self.Config.VanillaConfigUpToDate = true
	end

	if Edited then
		self:SaveConfig()
	end

	self:GenerateNetworkData()
end

--[[
	Converts the NS2/DAK bans format into one compatible with Shine.
]]
function Plugin:NS2ToShine( Data )
	for i = 1, #Data do
		local Table = Data[ i ]
		local SteamID = Table.id and tostring( Table.id )

		if SteamID then
			Data[ SteamID ] = NS2EntryToShineEntry( Table )
		end

		Data[ i ] = nil
	end

	return Data
end

--[[
	Saves the Shine bans in the vanilla bans config
]]
function Plugin:ShineToNS2()
	local NS2Bans = {}

	for ID, Table in pairs( self.Config.Banned ) do
		NS2Bans[ #NS2Bans + 1 ] = {
			name = Table.Name,
			id = tonumber( ID ),
			reason = Table.Reason,
			time = Table.UnbanTime,
			bannedby = Table.BannedBy,
			bannerid = Table.BannerID,
			duration = Table.Duration
		}
	end

	Shine.SaveJSONFile( NS2Bans, self.VanillaConfig )
end

function Plugin:GenerateNetworkData()
	local BanData = TableCopy( self.Config.Banned )

	local NetData = self.BanNetworkData
	local ShouldSort = NetData == nil

	NetData = NetData or {}

	--Remove all the bans we already know about.
	for i = 1, #NetData do
		local ID = NetData[ i ].ID

		--Update ban data.
		if BanData[ ID ] then
			NetData[ i ] = BanData[ ID ]
			NetData[ i ].ID = ID

			BanData[ ID ] = nil
		end
	end

	--Fill in the rest at the end of the network list.
	for ID, Data in pairs( BanData ) do
		NetData[ #NetData + 1 ] = Data
		Data.ID = ID
	end

	-- On initial population, sort by expiry, starting at the soonest to expire.
	if ShouldSort then
		TableSort( NetData, function( A, B )
			-- Push permanent bans back to the end of the list.
			if not A.UnbanTime or A.UnbanTime == 0 then
				return false
			end

			if not B.UnbanTime or B.UnbanTime == 0 then
				return true
			end

			return A.UnbanTime < B.UnbanTime
		end )
	end

	self.BanNetworkData = NetData
end

--[[
	Checks bans on startup.
]]
function Plugin:CheckBans()
	local Bans = self.Config.Banned
	local Edited

	for ID, Data in pairs( Bans ) do
		if self:IsBanExpired( Data ) then
			self:RemoveBan( ID, true )
			Edited = true
		end
	end

	if Edited then
		self:SaveConfig()
	end

	return Edited
end

function Plugin:SendHTTPRequest( ID, PostParams, Operation, Revert )
	TableShallowMerge( self.Config.BansSubmitArguments, PostParams )

	local Callbacks = {
		OnSuccess = function( Data )
			self.Logger:Debug( "Received response from server for %s of %s", Operation, ID )

			self.Retries[ ID ] = nil

			if not Data then
				self.Logger:Error( "Received no repsonse for %s of %s.", Operation, ID )
				return
			end

			local Decoded, Pos, Err = Decode( Data )
			if not Decoded then
				self.Logger:Error( "Received invalid JSON for %s of %s. Error: %s", Operation, ID, Err )
				self.Logger:Debug( "Response content:\n%s", Data )
				return
			end

			if Decoded.success == false then
				Revert()
				self:SaveConfig()
				self.Logger:Info( "Server rejected %s of %s, reverting...", Operation, ID )
			end
		end,
		OnFailure = function()
			self.Retries[ ID ] = nil
			self.Logger:Error( "Sending %s for %s timed out after %i retries.", Operation, ID,
				self.Config.MaxSubmitRetries )
		end
	}

	self.Retries[ ID ] = true

	self.Logger:Debug( "Sending %s of %s to: %s", Operation, ID, self.Config.BansSubmitURL )

	Shine.HTTPRequestWithRetry( self.Config.BansSubmitURL, "POST", PostParams,
		Callbacks, self.Config.MaxSubmitRetries, self.Config.SubmitTimeout )
end

--[[
	Registers a ban.
	Inputs: Steam ID, player name, ban duration in seconds, name of player performing the ban.
	Output: Success.
]]
function Plugin:AddBan( ID, Name, Duration, BannedBy, BanningID, Reason )
	if not tonumber( ID ) then
		ID = Shine.SteamIDToNS2( ID )

		if not ID then
			return false, "invalid Steam ID"
		end
	end

	ID = tostring( ID )

	local BanData = {
		ID = ID,
		Name = Name,
		Duration = Duration,
		UnbanTime = Duration ~= 0 and ( Time() + Duration ) or 0,
		BannedBy = BannedBy,
		BannerID = BanningID,
		Reason = Reason,
		Issued = Time()
	}

	self.Config.Banned[ ID ] = BanData
	self:SaveConfig()
	self:AddBanToNetData( BanData )

	if self.Config.BansSubmitURL ~= "" and not self.Retries[ ID ] then
		self:SendHTTPRequest( ID, {
			bandata = Encode( BanData ),
			unban = 0
		}, "ban", function()
			-- The web request told us that they shouldn't be banned.
			self.Config.Banned[ ID ] = nil
			self:NetworkUnban( ID )
		end )
	end

	if self.Config.BanSharerOnSharedBan then
		-- If the player has the game shared to them, ban the player sharing it.
		local function BanSharer( IsBannedAlready, Sharer )
			if IsBannedAlready or not Sharer then return end

			self:AddBan( Sharer, "<unknown>", Duration, BannedBy, BanningID, "Sharing to a banned account." )
		end
		BanSharer( self:CheckFamilySharing( ID, false, BanSharer ) )
	end

	Hook.Call( "OnPlayerBanned", ID, Name, Duration, BannedBy, Reason )

	return true
end

--[[
	Removes a ban.
	Input: Steam ID.
]]
function Plugin:RemoveBan( ID, DontSave, UnbannerID )
	ID = tostring( ID )

	local BanData = self.Config.Banned[ ID ]
	if not BanData then return end

	self.Config.Banned[ ID ] = nil
	self:NetworkUnban( ID )

	if self.Config.BansSubmitURL ~= "" and not self.Retries[ ID ] then
		self:SendHTTPRequest( ID, {
			unbandata = Encode{
				ID = ID,
				UnbannerID = UnbannerID or 0
			},
			unban = 1
		}, "unban", function()
			-- The web request told us that they shouldn't be unbanned.
			self.Config.Banned[ ID ] = BanData
			self:AddBanToNetData( BanData )
		end )
	end

	Hook.Call( "OnPlayerUnbanned", ID )

	if DontSave then return end

	self:SaveConfig()
end

Plugin.OperationSuffix = ""
Plugin.CommandNames = {
	Ban = { "sh_ban", "ban" },
	BanID = { "sh_banid", "banid" },
	Unban = { "sh_unban", "unban" }
}

function Plugin:PerformBan( Target, Player, BanningName, Duration, Reason )
	local BanMessage = StringFormat( "Banned from server by %s %s: %s",
		BanningName,
		string.TimeToDuration( Duration ),
		Reason )

	Server.DisconnectClient( Target, BanMessage )
end

--[[
	Creates the plugins console/chat commands.
]]
function Plugin:CreateBanCommands()
	--[[
		Bans by name/Steam ID when in the server.
	]]
	local function Ban( Client, Target, Duration, Reason )
		Duration = Duration * 60
		local ID = tostring( Target:GetUserId() )

		--We're currently waiting for a response on this ban.
		if self.Retries[ ID ] then
			if Client then
				self:SendTranslatedError( Client, "PLAYER_REQUEST_IN_PROGRESS", {
					ID = ID
				} )
			end
			Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.",
				true, ID )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Player = Target:GetControllingPlayer()
		local TargetName = Player:GetName()

		self:AddBan( ID, TargetName, Duration, BanningName, BanningID, Reason )
		self:PerformBan( Target, Player, BanningName, Duration, Reason )

		local DurationString = string.TimeToDuration( Duration )

		self:SendTranslatedMessage( Client, "PLAYER_BANNED", {
			TargetName = TargetName,
			Duration = Duration,
			Reason = Reason
		} )
		Shine:AdminPrint( nil, "%s banned %s%s %s.", true,
			Shine.GetClientInfo( Client ),
			Shine.GetClientInfo( Target ),
			self.OperationSuffix, DurationString )
	end
	local BanCommand = self:BindCommand( self.CommandNames.Ban[ 1 ], self.CommandNames.Ban[ 2 ], Ban )
	BanCommand:AddParam{ Type = "client", NotSelf = true }
	BanCommand:AddParam{ Type = "time", Units = "minutes", Min = 0, Round = true, Optional = true,
		Default = self.Config.DefaultBanTime }
	BanCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true,
		Default = "No reason given.", Help = "reason" }
	BanCommand:Help( StringFormat( "Bans the given player%s for the given time in minutes. 0 is a permanent ban.",
		self.OperationSuffix ) )

	--[[
		Unban by Steam ID.
	]]
	local function Unban( Client, ID )
		ID = tostring( ID )

		if self.Config.Banned[ ID ] then
			--We're currently waiting for a response on this ban.
			if self.Retries[ ID ] then
				if Client then
					self:SendTranslatedError( Client, "PLAYER_REQUEST_IN_PROGRESS", {
						ID = ID
					} )
				end
				Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.",
					true, ID )

				return
			end

			local Unbanner = ( Client and Client.GetUserId and Client:GetUserId() ) or 0

			self:RemoveBan( ID, nil, Unbanner )
			Shine:AdminPrint( nil, "%s unbanned %s%s.", true, Shine.GetClientInfo( Client ),
				ID, self.OperationSuffix )

			return
		end

		local ErrorText = StringFormat( "%s is not banned%s.", ID, self.OperationSuffix )

		if Client then
			self:SendTranslatedError( Client, "ERROR_NOT_BANNED", {
				ID = ID
			} )
		end
		Shine:AdminPrint( Client, ErrorText )
	end
	local UnbanCommand = self:BindCommand( self.CommandNames.Unban[ 1 ], self.CommandNames.Unban[ 2 ], Unban )
	UnbanCommand:AddParam{ Type = "steamid", Error = "Please specify a Steam ID to unban.", IgnoreCanTarget = true }
	UnbanCommand:Help( StringFormat( "Unbans the given Steam ID%s.", self.OperationSuffix ) )

	--[[
		Ban by Steam ID whether they're in the server or not.
	]]
	local function BanID( Client, ID, Duration, Reason )
		Duration = Duration * 60

		local IDString = tostring( ID )

		--We're currently waiting for a response on this ban.
		if self.Retries[ IDString ] then
			if Client then
				self:SendTranslatedError( Client, "PLAYER_REQUEST_IN_PROGRESS", {
					ID = ID
				} )
			end
			Shine:AdminPrint( Client, "Please wait for the current ban request on %s to finish.",
				true, IDString )

			return
		end

		local BanningName = Client and Client:GetControllingPlayer():GetName() or "Console"
		local BanningID = Client and Client:GetUserId() or 0
		local Target = Shine.GetClientByNS2ID( ID )
		local TargetName = "<unknown>"

		if Target then
			TargetName = Target:GetControllingPlayer():GetName()
		end

		if self:AddBan( IDString, TargetName, Duration, BanningName, BanningID, Reason ) then
			local DurationString = string.TimeToDuration( Duration )

			Shine:AdminPrint( nil, "%s banned %s[%s]%s %s.", true, Shine.GetClientInfo( Client ),
				TargetName, IDString, self.OperationSuffix, DurationString )

			if Target then
				self:PerformBan( Target, Target:GetControllingPlayer(), BanningName, Duration, Reason )
				self:SendTranslatedMessage( Client, "PLAYER_BANNED", {
					TargetName = TargetName,
					Duration = Duration,
					Reason = Reason
				} )
			end

			return
		end

		if Client then
			self:NotifyTranslatedError( Client, "ERROR_INVALID_STEAMID" )
		end
		Shine:AdminPrint( Client, "Invalid Steam ID for banning." )
	end
	local BanIDCommand = self:BindCommand( self.CommandNames.BanID[ 1 ], self.CommandNames.BanID[ 2 ], BanID )
	BanIDCommand:AddParam{ Type = "steamid", Error = "Please specify a Steam ID to ban." }
	BanIDCommand:AddParam{ Type = "time", Units = "minutes", Min = 0, Round = true, Optional = true,
		Default = self.Config.DefaultBanTime }
	BanIDCommand:AddParam{ Type = "string", Optional = true, TakeRestOfLine = true,
		Default = "No reason given.", Help = "reason" }
	BanIDCommand:Help( StringFormat( "Bans the given Steam ID%s for the given time in minutes. 0 is a permanent ban.",
		self.OperationSuffix ) )
end

function Plugin:CreateCommands()
	self:CreateBanCommands()

	local function ListBans( Client )
		if not next( self.Config.Banned ) then
			Shine:AdminPrint( Client, "There are no bans on record." )
			return
		end

		Shine:AdminPrint( Client, "Currently stored bans:" )
		for ID, BanTable in pairs( self.Config.Banned ) do
			local TimeRemaining = BanTable.UnbanTime == 0 and "Forever"
				or string.TimeToString( BanTable.UnbanTime - Time() )

			Shine:AdminPrint( Client, "- ID: %s. Name: %s. Time remaining: %s. Reason: %s",
				true, ID, BanTable.Name or "<unknown>", TimeRemaining,
				BanTable.Reason or "No reason given." )
		end
	end
	local ListBansCommand = self:BindCommand( "sh_listbans", nil, ListBans )
	ListBansCommand:Help( "Lists all stored bans from Shine." )

	local function ForceWebSync( Client )
		if self.Config.BansURL == "" then
			return
		end

		self:LoadBansFromWeb()

		Shine:AdminPrint( Client, "Updating bans from the web..." )
	end
	local ForceSyncCommand = self:BindCommand( "sh_forcebansync", nil, ForceWebSync )
	ForceSyncCommand:Help( "Forces the bans plugin to reload ban data from the web." )
end

function Plugin:GetBanEntry( ID )
	return self.Config.Banned[ tostring( ID ) ]
end

function Plugin:IsBanExpired( BanEntry )
	return BanEntry.UnbanTime and BanEntry.UnbanTime ~= 0 and BanEntry.UnbanTime <= Time()
end

function Plugin:IsIDBanned( ID )
	local BanEntry = self:GetBanEntry( ID )
	if not BanEntry or self:IsBanExpired( BanEntry ) then return false end

	return true
end

--[[
	Checks whether the given ID is family sharing with a banned account.
]]
function Plugin:CheckFamilySharing( ID, NoAPIRequest, OnAsyncResponse )
	local RequestParams = {
		steamid = ID
	}

	local Sharer = Shine.ExternalAPIHandler:GetCachedValue( "Steam", "IsPlayingSharedGame", RequestParams )
	if Sharer ~= nil then
		if not Sharer then return false end

		return self:IsIDBanned( Sharer ), Sharer
	end

	if NoAPIRequest then return false end
	if not Shine.ExternalAPIHandler:HasAPIKey( "Steam" ) then return false end

	Shine.ExternalAPIHandler:PerformRequest( "Steam", "IsPlayingSharedGame", RequestParams, {
		OnSuccess = self:WrapCallback( function( Sharer )
			if not Sharer then
				return OnAsyncResponse( false )
			end

			self:Print( "Player %s is playing through family sharing from account with ID: %s.", true, ID, Sharer )

			OnAsyncResponse( self:IsIDBanned( Sharer ), Sharer )
		end ),
		OnFailure = function()
			self:Print( "Failed to receive response from Steam for user %s's family sharing status.",
				true, ID )
		end
	} )

	return false
end

function Plugin:KickForFamilySharing( Client, Sharer )
	self:Print( "Kicking %s for family sharing with a banned account. Sharer ID: %s.", true,
			Shine.GetClientInfo( Client ), Sharer )
	Server.DisconnectClient( Client, "Family sharing with a banned account." )
end

--[[
	On client connect, check if they're family sharing without an API request.

	This will pick up on the result of a request sent on connection that's finished now
	the client's connected.
]]
function Plugin:ClientConnect( Client )
	if not self.Config.CheckFamilySharing then return end

	local IsSharing, Sharer = self:CheckFamilySharing( Client:GetUserId(), true )
	if IsSharing then
		self:KickForFamilySharing( Client, Sharer )
	end
end

function Plugin:GetBanMessage( BanEntry )
	local Message = { "Banned from server" }

	if BanEntry.BannedBy then
		Message[ #Message + 1 ] = " by "
		Message[ #Message + 1 ] = BanEntry.BannedBy
	end

	Message[ #Message + 1 ] = " "

	local Duration = 0
	if BanEntry.Duration then
		Duration = BanEntry.Duration
	elseif BanEntry.UnbanTime and BanEntry.UnbanTime ~= 0 then
		Duration = BanEntry.UnbanTime - Time()
	end

	Message[ #Message + 1 ] = string.TimeToDuration( Duration )

	if BanEntry.Reason and BanEntry.Reason ~= "" then
		Message[ #Message + 1 ] = ": "
		Message[ #Message + 1 ] = BanEntry.Reason
	end

	if not StringFind( Message[ #Message ], "[%.!%?]$" ) then
		Message[ #Message + 1 ] = "."
	end

	return TableConcat( Message )
end

--[[
	Runs on client connection attempt.
	Rejects a client if they're on the ban list and still banned.
	If they're past their ban time, their ban is removed.
]]
function Plugin:CheckConnectionAllowed( ID )
	if self:IsIDBanned( ID ) then
		return false, self:GetBanMessage( self:GetBanEntry( ID ) )
	end

	self:RemoveBan( ID )

	if not self.Config.CheckFamilySharing then return end

	local IsSharingAndSharerBanned = self:CheckFamilySharing( ID, false, function( IsSharerBanned, Sharer )
		if not Sharer or not IsSharerBanned then return end

		-- Unlikely, but possible that the client's already loaded before Steam responds.
		local Target = Shine.GetClientByNS2ID( ID )
		if Target then
			self:KickForFamilySharing( Target, Sharer )
		end
	end )

	if IsSharingAndSharerBanned then return false, "Family sharing with a banned account." end
end

function Plugin:ClientDisconnect( Client )
	if not self.BanNetworkedClients then return end

	self.BanNetworkedClients[ Client ] = nil
end

function Plugin:NetworkBan( BanData, Client )
	if not Client and not self.BanNetworkedClients then return end

	local NetData = {
		ID = BanData.ID,
		Name = BanData.Name or "Unknown",
		Duration = BanData.Duration or 0,
		UnbanTime = BanData.UnbanTime,
		BannedBy = BanData.BannedBy or "Unknown",
		BannerID = BanData.BannerID or 0,
		Reason = BanData.Reason or "",
		Issued = BanData.Issued or 0
	}

	if Client then
		self:SendNetworkMessage( Client, "BanData", NetData, true )
	else
		for Client in pairs( self.BanNetworkedClients ) do
			self:SendNetworkMessage( Client, "BanData", NetData, true )
		end
	end
end

function Plugin:NetworkUnban( ID )
	local NetData = self.BanNetworkData

	if NetData then
		for i = 1, #NetData do
			local Data = NetData[ i ]

			--Remove the ban from the network data.
			if Data.ID == ID then
				TableRemove( NetData, i )

				--Anyone on an index bigger than this one needs to go down 1.
				if self.BanNetworkedClients then
					for Client, Index in pairs( self.BanNetworkedClients ) do
						if Index > i then
							self.BanNetworkedClients[ Client ] = Index - 1
						end
					end
				end

				break
			end
		end
	end

	if not self.BanNetworkedClients then return end

	for Client in pairs( self.BanNetworkedClients ) do
		self:SendNetworkMessage( Client, "Unban", { ID = ID }, true )
	end
end

function Plugin:ReceiveRequestBanData( Client, Data )
	if not Shine:GetPermission( Client, self.ListPermission ) then return end

	self.BanNetworkedClients = self.BanNetworkedClients or {}

	self.BanNetworkedClients[ Client ] = self.BanNetworkedClients[ Client ] or 1
	local Index = self.BanNetworkedClients[ Client ]

	local NetworkData = self.BanNetworkData

	if not NetworkData then return end

	for i = Index, Clamp( Index + self.MAX_BAN_PER_NETMESSAGE - 1, 0, #NetworkData ) do
		if NetworkData[ i ] then
			self:NetworkBan( NetworkData[ i ], Client )
		end
	end

	self.BanNetworkedClients[ Client ] = Clamp( Index + self.MAX_BAN_PER_NETMESSAGE,
		0, #NetworkData + 1 )
end

function Plugin:AddBanToNetData( BanData )
	self.BanNetworkData = self.BanNetworkData or {}

	local NetData = self.BanNetworkData

	for i = 1, #NetData do
		local Data = NetData[ i ]

		if Data.ID == BanData.ID then
			NetData[ i ] = BanData

			if self.BanNetworkedClients then
				for Client, Index in pairs( self.BanNetworkedClients ) do
					if Index > i then
						self:NetworkBan( BanData, Client )
					end
				end
			end

			return
		end
	end

	NetData[ #NetData + 1 ] = BanData
end

Shine.LoadPluginModule( "logger.lua" )
