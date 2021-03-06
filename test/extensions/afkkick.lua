--[[
	AFK kick plugin test.
]]

local UnitTest = Shine.UnitTest
local AFKKick = UnitTest:LoadExtension( "afkkick" )
if not AFKKick then return end

local Validator = rawget( AFKKick, "ConfigValidator" )

AFKKick = UnitTest.MockOf( AFKKick )

AFKKick.Config.WarnActions.NoImmunity = {
	"MOVE_TO_SPECTATE"
}
AFKKick.Config.WarnActions.PartialImmunity = {
	"MOVE_TO_READY_ROOM"
}

UnitTest:Test( "ValidateConfig - All valid", function( Assert )
	local NeedsUpdate = Validator:Validate( AFKKick.Config )
	Assert:False( NeedsUpdate )
	Assert:ArrayEquals( { "MOVE_TO_SPECTATE" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MOVE_TO_READY_ROOM" }, AFKKick.Config.WarnActions.PartialImmunity )
end )

AFKKick.Config.WarnActions.NoImmunity = {
	"MOVE_TO_SPECTATE", "MOVE_TO_READY_ROOM"
}
AFKKick.Config.WarnActions.PartialImmunity = {
	"MOVE_TO_SPECTATE", "MOVE_TO_READY_ROOM"
}

UnitTest:Test( "ValidateConfig - Both move to ready room and spectate", function( Assert )
	local NeedsUpdate = Validator:Validate( AFKKick.Config )
	Assert:True( NeedsUpdate )
	Assert:ArrayEquals( { "MOVE_TO_SPECTATE" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MOVE_TO_SPECTATE" }, AFKKick.Config.WarnActions.PartialImmunity )

	AFKKick.Config.WarnActions.NoImmunity = {
		"MOVE_TO_READY_ROOM", "MOVE_TO_SPECTATE"
	}
	AFKKick.Config.WarnActions.PartialImmunity = {
		"MOVE_TO_READY_ROOM", "MOVE_TO_SPECTATE"
	}
	NeedsUpdate = Validator:Validate( AFKKick.Config )

	Assert:True( NeedsUpdate )
	Assert:ArrayEquals( { "MOVE_TO_READY_ROOM" }, AFKKick.Config.WarnActions.NoImmunity )
	Assert:ArrayEquals( { "MOVE_TO_READY_ROOM" }, AFKKick.Config.WarnActions.PartialImmunity )
end )

AFKKick.Config.WarnActions.NoImmunity = false
AFKKick.Config.WarnActions.PartialImmunity = false

UnitTest:Test( "ValidateConfig - Missing immunity actions", function( Assert )
	local NeedsUpdate = Validator:Validate( AFKKick.Config )

	Assert:True( NeedsUpdate )
	Assert:IsType( AFKKick.Config.WarnActions.NoImmunity, "table" )
	Assert:IsType( AFKKick.Config.WarnActions.PartialImmunity, "table" )
end )

AFKKick.Config.WarnMinPlayers = 10
AFKKick.Config.MinPlayers = 0

UnitTest:Test( "ValidateConfig - WarnMinPlayers <= MinPlayers", function( Assert )
	local NeedsUpdate = Validator:Validate( AFKKick.Config )

	Assert:True( NeedsUpdate )
	Assert:Equals( AFKKick.Config.MinPlayers, AFKKick.Config.WarnMinPlayers )
end )

local OldGetClientInfo = Shine.GetClientInfo
AFKKick.Print = function() end
Shine.GetClientInfo = function() return "" end
AFKKick.CanKickForConnectingClient = function() return true end

UnitTest:Test( "KickOnConnect", function( Assert )
	AFKKick.Config.KickOnConnect = true
	AFKKick.Config.KickTime = 2

	AFKKick.Users = Shine.Map( {
		[ 1 ] = {
			AFKAmount = 2.5 * 60
		},
		[ 2 ] = {
			AFKAmount = 0.5
		},
		[ 3 ] = {
			AFKAmount = 5 * 60
		}
	} )

	-- Should kick client 3
	local Kicked
	AFKKick.KickClient = function( self, Client )
		Assert:Equals( 3, Client )
		Kicked = true
	end

	Assert:Nil( AFKKick:CheckConnectionAllowed( 123456 ) )
	Assert:True( Kicked )

	-- Should now not kick anyone.
	AFKKick.Config.KickTime = 10
	Kicked = false

	Assert:Nil( AFKKick:CheckConnectionAllowed( 123456 ) )
	Assert:False( Kicked )
end, function()
	AFKKick.Config.KickOnConnect = false
end )

Shine.GetClientInfo = OldGetClientInfo
