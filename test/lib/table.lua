--[[
	Table library extension tests.
]]

local UnitTest = Shine.UnitTest

UnitTest:Test( "Reverse", function( Assert )
	local Input = { 1, 2, 3, 4, 5, 6 }
	Assert:ArrayEquals( { 6, 5, 4, 3, 2, 1 }, table.Reverse( Input ) )
end )

UnitTest:Test( "RemoveByValue", function( Assert )
	local Input = { 1, 2, 3, 4, 5, 6 }
	table.RemoveByValue( Input, 3 )

	Assert:ArrayEquals( { 1, 2, 4, 5, 6 }, Input )
end )

UnitTest:Test( "Add", function( Assert )
	local Source = { 4, 5, 6 }
	local Destination = { 1, 2, 3 }

	Destination = table.Add( Destination, Source )

	Assert:ArrayEquals( { 1, 2, 3, 4, 5 , 6 }, Destination )
end )

UnitTest:Test( "Mixin", function( Assert )
	local Source = {
		Cake = true,
		MoreCake = true,
		SoMuchCake = true
	}
	local Destination = {}
	table.Mixin( Source, Destination, {
		"Cake", "MoreCake"
	} )

	Assert:True( Destination.Cake )
	Assert:True( Destination.MoreCake )
	Assert:Nil( Destination.SoMuchCake )
end )

UnitTest:Test( "ShallowMerge", function( Assert )
	local Source = {
		Cake = true,
		MoreCake = false
	}
	local Destination = {
		Cake = false
	}

	table.ShallowMerge( Source, Destination )

	Assert:False( Destination.Cake )
	Assert:False( Destination.MoreCake )

	-- Add an inherited value.
	setmetatable( Destination, {
		__index = {
			InheritedKey = true
		}
	} )
	Source.InheritedKey = false

	-- Default is standard indexing, so it will see the inherited value.
	table.ShallowMerge( Source, Destination )

	Assert:True( Destination.InheritedKey )

	-- Now the raw flag means it will override the inherited value.
	table.ShallowMerge( Source, Destination, true )

	Assert:False( Destination.InheritedKey )
end )

UnitTest:Test( "HasValue", function( Assert )
	local Table = {
		1, 2, 4, 3, 5, 6
	}

	local Exists, Index = table.HasValue( Table, 3 )
	Assert:True( Exists )
	Assert:Equals( 4, Index )

	Exists, Index = table.HasValue( Table, 7 )
	Assert:False( Exists )
	Assert:Nil( Index )
end )

UnitTest:Test( "InsertUnique", function( Assert )
	local Table = {
		1, 2, 3
	}

	local Inserted = table.InsertUnique( Table, 4 )
	Assert:True( Inserted )
	Assert:ArrayEquals( { 1, 2, 3, 4 }, Table )

	Inserted = table.InsertUnique( Table, 4 )
	Assert:False( Inserted )
	Assert:ArrayEquals( { 1, 2, 3, 4 }, Table )
end )

UnitTest:Test( "Build", function( Assert )
	local Base = {}
	local ReallySubChild = table.Build( Base, "Child", "SubChild", "ReallySubChild" )

	Assert:IsType( Base.Child, "table" )
	Assert:IsType( Base.Child.SubChild, "table" )
	Assert:IsType( Base.Child.SubChild.ReallySubChild, "table" )

	Assert:Equals( Base.Child.SubChild.ReallySubChild, ReallySubChild )

	-- Should not overwrite if tables already exist.
	Base.Child.Cake = true
	Assert:Equals( ReallySubChild, table.Build( Base, "Child", "SubChild", "ReallySubChild" ) )
	Assert:True( Base.Child.Cake )
end )

UnitTest:Test( "QuickShuffle", function( Assert )
	local Data = { 1, 2, 3, 4, 5, 6 }
	table.QuickShuffle( Data )
	Assert:Equals( 6, #Data )
	for i = 1, 6 do
		Assert:NotNil( Data[ i ] )
	end
end )

UnitTest:Test( "QuickCopy", function( Assert )
	local Table = { 1, 2, {}, 4 }
	local Copy = table.QuickCopy( Table )

	Assert:NotEquals( Table, Copy )
	for i = 1, #Table do
		Assert:Equals( Table[ i ], Copy[ i ] )
	end
end )

UnitTest:Test( "ShallowCopy", function( Assert )
	local Table = { 1, 2, 3, Key = "Value" }
	local Copy = table.ShallowCopy( Table )

	Assert:NotEquals( Table, Copy )
	for i = 1, #Table do
		Assert:Equals( Table[ i ], Copy[ i ] )
	end
	Assert:Equals( "Value", Copy.Key )
end )

do
	local function LT( A, B )
		return A.Index < B.Index
	end
	local ComparableObjects = {
		setmetatable( { Index = 1 }, { __lt = LT } ),
		setmetatable( { Index = 2 }, { __lt = LT } )
	}
	local function GetTestTable()
		return {
			Key1 = true,
			Key2 = true,
			Key3 = true,
			[ ComparableObjects[ 1 ] ] = true,
			[ ComparableObjects[ 2 ] ] = true,
			true, true, true
		}
	end

	UnitTest:Test( "GetKeys", function( Assert )
		local Table = GetTestTable()

		local Keys, Count = table.GetKeys( Table )
		Assert:Equals( 8, Count )
		for i = 1, Count do
			Assert:True( Table[ Keys[ i ] ] )
			Table[ Keys[ i ] ] = nil
		end
	end )

	local function BuildIteratorTest( Iterator )
		return function( Assert )
			local Table = GetTestTable()
			local Keys = {}

			for Key, Value in Iterator( Table ) do
				Assert:True( Value )
				Assert:True( Table[ Key ] )
				Table[ Key ] = nil
				Keys[ #Keys + 1 ] = Key
			end

			return Keys
		end
	end

	UnitTest:Test( "RandomPairs", BuildIteratorTest( RandomPairs ) )
	UnitTest:Test( "SortedPairs", function( Assert )
		local Keys = BuildIteratorTest( SortedPairs )( Assert )
		Assert:ArrayEquals( { 1, 2, 3, "Key1", "Key2", "Key3",
			ComparableObjects[ 1 ], ComparableObjects[ 2 ] }, Keys )
	end )
end

UnitTest:Test( "ArraysEqual", function( Assert )
	local Left = { 1, 2, 3 }
	local Right = { 1, 2, 3 }

	Assert:True( table.ArraysEqual( Left, Right ) )

	Left[ 4 ] = 5
	Right[ 4 ] = 4
	Assert:False( table.ArraysEqual( Left, Right ) )

	Left[ 4 ] = 4
	Right[ 5 ] = 5
	Assert:False( table.ArraysEqual( Left, Right ) )
end )

UnitTest:Test( "AsEnum", function( Assert )
	local Values = {
		"This", "Is", "An", "Enum"
	}
	local Enum = table.AsEnum( Values )
	Assert:ArrayEquals( Values, Enum )
	for i = 1, #Values do
		Assert:Equals( Values[ i ], Enum[ Values[ i ] ] )
	end
end )

UnitTest:Test( "AsEnum with transformer", function( Assert )
	local Values = {
		"This", "Is", "An", "Enum"
	}
	local Enum = table.AsEnum( Values, function( Index ) return Index end )
	Assert:ArrayEquals( Values, Enum )
	for i = 1, #Values do
		Assert:Equals( i, Enum[ Values[ i ] ] )
	end
end )

local StringToEscape = "This is\n\r\f\b\t\\a \"string\" with áéíóú unicode."..string.char( 0 )
local ExpectedJSON = string.gsub( [[{
	"Array": [
		{
			"String": "This is\n\r\f\b\t\\a \"string\" with áéíóú unicode.\u0000"
		},
		null,
		"This is\n\r\f\b\t\\a \"string\" with áéíóú unicode.\u0000",
		1.5
	],
	"Boolean": true,
	"Number": 1.5,
	"Object": {
		"1": "This is\n\r\f\b\t\\a \"string\" with áéíóú unicode.\u0000",
		"2": 1.5,
		"Nested": {
			"Array": [ 1, 2, 3 ],
			"More": {}
		}
	},
	"String": "This is\n\r\f\b\t\\a \"string\" with áéíóú unicode.\u0000"
}]], "\t", "    " )
local Data = {
	Array = {
		{
			String = StringToEscape
		},
		nil,
		StringToEscape,
		1.5
	},
	Boolean = true,
	Number = 1.5,
	Object = {
		Nested = {
			Array = { 1, 2, 3 },
			More = setmetatable( {}, { __jsontype = "object" } )
		},
		StringToEscape,
		1.5
	},
	String = StringToEscape
}
-- Will deserialised the array part of "Object" as string keys.
local ExpectedData = table.Copy( Data )
ExpectedData.Object[ "1" ] = ExpectedData.Object[ 1 ]
ExpectedData.Object[ 1 ] = nil
ExpectedData.Object[ "2" ] = ExpectedData.Object[ 2 ]
ExpectedData.Object[ 2 ] = nil

UnitTest:Test( "ToJSON with pretty printing", function( Assert )
	local JSON = table.ToJSON( Data )
	Assert.Equals( "Output should be exactly as specified", ExpectedJSON, JSON )
	Assert.DeepEquals( "Deserialised output should be exactly the same as input",
		ExpectedData, json.decode( JSON ) )
end )

ExpectedJSON = [[{"Array":[{"String":"This is\n\r\f\b\t\\a \"string\" with áéíóú unicode.\u0000"},null,]]
..[["This is\n\r\f\b\t\\a \"string\" with áéíóú unicode.\u0000",1.5],"Boolean":true,"Number":1.5,]]
..[["Object":{"1":"This is\n\r\f\b\t\\a \"string\" with áéíóú unicode.\u0000","2":1.5,"Nested":{"Array":[1,2,3],]]
..[["More":{}}},"String":"This is\n\r\f\b\t\\a \"string\" with áéíóú unicode.\u0000"}]]

UnitTest:Test( "ToJSON without pretty printing", function( Assert )
	local JSON = table.ToJSON( Data, { PrettyPrint = false } )
	Assert.Equals( "Output should be exactly as specified", ExpectedJSON, JSON )
	Assert.DeepEquals( "Deserialised output should be exactly the same as input",
		ExpectedData, json.decode( JSON ) )
end )

local DataWithCycle = {}
DataWithCycle.Cycle = DataWithCycle

UnitTest:Test( "ToJSON rejects tables with cycles", function( Assert )
	local Success, Err = pcall( table.ToJSON, DataWithCycle )
	Assert.False( "Should reject data with cycles", Success )
	Assert.True( "Error should reference the cycle", string.EndsWith( Err, "Cycle in input table" ) )
end )

local DataWithUnsupportedKey = {
	[ {} ] = true
}
UnitTest:Test( "ToJSON rejects tables with unsupported key types", function( Assert )
	local Success, Err = pcall( table.ToJSON, DataWithUnsupportedKey )
	Assert.False( "Should reject data with unsupported key type", Success )
	Assert.True( "Error should reference the value type", string.EndsWith( Err, "Unsupported table key type: table" ) )
end )

local DataWithUnsupportedValue = {
	Function = function() end
}

UnitTest:Test( "ToJSON rejects tables with unsupported value types", function( Assert )
	local Success, Err = pcall( table.ToJSON, DataWithUnsupportedValue )
	Assert.False( "Should reject data with unsupported value type", Success )
	Assert.True( "Error should reference the value type", string.EndsWith( Err, "Unsupported value type: function" ) )
end )
