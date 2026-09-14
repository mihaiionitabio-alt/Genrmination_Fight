--[========[
Revision 4 engineering reference | 13 September 2026
Authority: ReplicatedStorage.LabKinds
Full design, defect history and extension specifications: ServerStorage.GameDocumentation.
Do not require the documentation module from gameplay or replicate its prose to clients.
Purpose: Equipment catalog
Future change: Add one Kind with inputs, outputs, wait duration, and display text. Keep simulation values explicit.
Preserve dependencies: LabEquipment consumption and treatment paths; generator Kind attributes.
Acceptance cases: Unknown Kind, missing input, invalid output, full destination, and a complete valid cycle.
]========]
-- LabKinds : what each kind of basic laboratory equipment does.
-- Keyed by the Kind attribute the generator writes on every item, so
-- any number of copies anywhere in the building behave the same.

local K = {}

K.Items = {
	TRAY    = "Sample Tray",
	GROUND  = "Ground Sample",
	DRIED   = "Dried Sample",
	SPUN    = "Separated Sample",
	CULTURE = "Culture Plate",
	WASTE   = "Used Material",
	CLEAN   = "Clean Glassware",
}
local I = K.Items

local function f(n, dp) return string.format("%." .. dp .. "f", n) end
local function rnd(a, b) return a + math.random() * (b - a) end

K.Actions = {
	["Workbench"] = {action = "Set out a sample", wait = 1.2, produces = {I.TRAY},
		log = function() return "Sample laid out on the bench." end},
	["Island Bench"] = {action = "Set out a sample", wait = 1.2, produces = {I.TRAY},
		log = function() return "Sample laid out on the island bench." end},
	["Base Cabinet Run"] = {action = "Open the cabinet", wait = 0.8,
		log = function() return "Consumables drawn from the cabinet." end},
	["Desk"] = {action = "Write up the record", wait = 1.2,
		log = function() return "Notes entered in the log book." end},

	["Sink Unit"] = {action = "Wash glassware", wait = 2.0, produces = {I.CLEAN},
		log = function() return "Glassware rinsed and set to drain." end},
	["Fume Hood"] = {action = "Work under extraction", wait = 2.5, uvLight = true,
		log = function() return "Extraction running at " .. f(rnd(0.4, 0.6), 2) .. " m/s face velocity." end},

	["Laboratory Mill"] = {action = "Grind the sample", wait = 2.0,
		consumes = I.TRAY, produces = {I.GROUND}, activeColour = Color3.fromRGB(200, 160, 60),
		log = function() return "Ground for two minutes; chamber cleaned afterwards." end},
	["Sieve Shaker"] = {action = "Sieve the sample", wait = 2.0,
		log = function() return f(rnd(45, 80), 0) .. "% passed the working mesh." end},
	["Drying Oven"] = {action = "Dry the sample", wait = 3.5,
		consumes = I.TRAY, produces = {I.DRIED}, activeColour = Color3.fromRGB(200, 60, 50),
		log = function() return "Oven holding " .. f(rnd(101, 105), 1) .. " C." end},
	["Centrifuge"] = {action = "Spin the sample", wait = 2.5,
		consumes = I.TRAY, produces = {I.SPUN},
		log = function() return f(rnd(3000, 12000), 0) .. " rpm for " .. math.random(5, 20) .. " minutes." end},
	["Incubator"] = {action = "Incubate the sample", wait = 3.0,
		consumes = I.TRAY, produces = {I.CULTURE}, activeColour = Color3.fromRGB(255, 170, 0),
		log = function() return "Holding " .. f(rnd(19, 31), 1) .. " C; door log updated." end},
	["Autoclave"] = {action = "Sterilize a load", wait = 3.0,
		consumes = I.WASTE, activeColour = Color3.fromRGB(0, 120, 255),
		log = function() return "Cycle complete at 121 C; indicator strip filed." end},
	["Waste Bin"] = {action = "Discard used material", wait = 0.8, consumes = I.WASTE,
		log = function() return "Waste segregated for removal." end},

	["Analytical Balance"] = {action = "Weigh the sample", wait = 1.5,
		log = function()
			local w = rnd(0.4, 25)
			return "Reading " .. f(w, w < 1 and 4 or 3) .. " g; balance levelled and zeroed."
		end},
	["Microscope"] = {action = "Examine the sample", wait = 1.5,
		log = function() return "Examined at " .. math.random(1, 4) * 10 .. "x." end},
	["pH Meter"] = {action = "Measure pH", wait = 1.2,
		log = function() return "pH " .. f(rnd(4.5, 9.0), 2) .. " at " .. f(rnd(19, 23), 1) .. " C." end},
	["Water Bath"] = {action = "Warm the sample", wait = 1.5,
		log = function() return "Bath steady at " .. f(rnd(30, 60), 1) .. " C." end},
	["Hot Plate Stirrer"] = {action = "Stir and heat", wait = 1.5,
		log = function() return "Stirring at " .. math.random(200, 900) .. " rpm." end},
	["Orbital Shaker"] = {action = "Shake the sample", wait = 1.5,
		log = function() return "Shaking at " .. math.random(80, 260) .. " rpm." end},
	["Desiccator"] = {action = "Cool the sample", wait = 1.8,
		consumes = I.DRIED, produces = {I.WASTE},
		log = function() return "Cooled over dry desiccant before the second weighing." end},
	["Computer Terminal"] = {action = "Enter the result", wait = 1.2,
		log = function() return "Result recorded against the sample number." end},

	["Refrigerator"] = {action = "Load / unload sample", wait = 1.2,
		log = function() return "Held at " .. f(rnd(2, 8), 1) .. " C." end},
	["Chest Freezer"] = {action = "Load / unload sample", wait = 1.2,
		log = function() return "Held at " .. f(rnd(-25, -16), 0) .. " C." end},
	["Sample Cabinet"] = {action = "File the sample", wait = 1.0,
		log = function() return "Filed by sample number." end},
	["Shelving Unit"] = {action = "Draw stock", wait = 0.8,
		log = function() return "Stock drawn; reorder level checked." end},
	["Storage Rack"] = {action = "Draw stock", wait = 0.8,
		log = function() return "Stock drawn from the rack." end},
	["Glassware Rack"] = {action = "Take clean glassware", wait = 0.8, produces = {I.CLEAN},
		log = function() return "Clean glassware taken from the rack." end},
	["Trolley"] = {action = "Load the trolley", wait = 0.8,
		log = function() return "Trolley loaded for transfer." end},
	["Filing Cabinet"] = {action = "Pull a file", wait = 0.8,
		log = function() return "File retrieved." end},
	["Locker Bank"] = {action = "Change clothing", wait = 1.2,
		log = function() return "Changed before entering the working area." end},
	["Gas Cylinder Rack"] = {action = "Check the cylinders", wait = 1.0,
		log = function() return "Cylinders chained; regulator pressure " .. math.random(20, 200) .. " bar." end},
	["Reagent Rack"] = {action = "Take a reagent", wait = 0.8,
		log = function() return "Reagent taken; bottle logged back in." end},
	["Test Tube Rack"] = {action = "Rack the tubes", wait = 0.8,
		log = function() return "Tubes racked and labelled." end},
	["Pipette Stand"] = {action = "Take a pipette", wait = 0.8,
		log = function() return "Pipette taken; last service date in date." end},

	["Germination Chamber"] = {action = "Load a germination test", wait = 2.5,
		consumes = I.TRAY, produces = {I.CULTURE}, activeColour = Color3.fromRGB(120, 200, 140),
		log = function() return "Test set at " .. f(rnd(18, 25), 1) .. " C, day count started." end},
	["Sample Divider"] = {action = "Divide the sample", wait = 1.8,
		consumes = I.GROUND, produces = {I.TRAY},
		log = function() return "Split into equal working portions." end},
	["Decontamination Unit"] = {action = "Run decontamination", wait = 2.2, consumes = I.WASTE,
		activeColour = Color3.fromRGB(150, 210, 255),
		log = function() return "Cycle complete; surfaces clear." end},
	["Water Distiller"] = {action = "Draw distilled water", wait = 1.2,
		log = function() return "Conductivity " .. f(rnd(0.5, 2.5), 1) .. " uS/cm." end},
	["Reference Sample Archive"] = {action = "File a reference sample", wait = 1.0,
		log = function() return "Filed against the reference register." end},
	["Optical Analyzer"] = {action = "Run an optical reading", wait = 1.8,
		log = function() return "Reading logged at " .. math.random(400, 800) .. " nm." end},
	["Electrophoresis Unit"] = {action = "Run a separation", wait = 2.0, activeColour = Color3.fromRGB(0, 120, 255),
		log = function() return "Run complete at " .. math.random(60, 150) .. " V." end},
	["Thermal Cycler"] = {action = "Run an amplification cycle", wait = 2.5, activeColour = Color3.fromRGB(255, 170, 0),
		log = function() return math.random(25, 40) .. " cycles complete." end},
	["Homogenizer"] = {action = "Homogenize the sample", wait = 1.5,
		log = function() return "Sample homogenized at " .. math.random(8000, 24000) .. " rpm." end},
	["Seed Counter"] = {action = "Count the sample", wait = 1.5,
		log = function() return math.random(200, 1200) .. " units counted." end},
	["Calibration Weight Set"] = {action = "Check calibration", wait = 1.0,
		log = function() return "Balance checked against certified weights." end},
	["Temperature Logger"] = {action = "Read the logger", wait = 0.6,
		log = function() return "Log downloaded; " .. f(rnd(2, 8), 1) .. " C average." end},

	["Plant Growth Chamber"] = {action = "Take / return plant", wait = 0.8},
	["Growth Hormone Mixer"] = {action = "Apply growth hormone", wait = 2.0},
	["GMO Injector"] = {action = "Inject GMO trait", wait = 2.4},
	["Nutrient Infuser"] = {action = "Infuse nutrients", wait = 1.8},
	["UV Growth Scanner"] = {action = "Scan plant development", wait = 1.5},
	["Pollination Station"] = {action = "Pollinate the plant", wait = 2.1},
	["Mutagenesis Chamber"] = {action = "Irradiate the sample", wait = 2.4,
		log = function() return math.random(100, 1000) .. " Gy dose logged; dosimeter reset." end},
	["Hormone Treatment Bench"] = {action = "Apply hormone treatment", wait = 2.0,
		log = function() return "Auxin/cytokinin mix dosed and logged." end},

	-- Cooperative role stations: LabEquipment special-cases these three
	-- kinds before ever reaching this table, so only the prompt flavour
	-- text below (action/wait) is actually used for them.
	["Sample Intake"]      = {action = "Log a sample", wait = 1.0},
	["Inspection Station"] = {action = "Inspect the batch", wait = 1.2},
	["Supervisor Console"] = {action = "Sign off the batch", wait = 1.5},

	["Fire Extinguisher"] = {action = "Check the extinguisher", wait = 1.0,
		log = function() return "Gauge in the green; inspection tag current." end},
	["First Aid Cabinet"] = {action = "Check the first aid kit", wait = 1.0,
		log = function() return "Contents complete." end},
	["Eyewash Station"] = {action = "Flush the eyewash", wait = 1.5,
		log = function() return "Weekly flush run; water clear." end},
}

K.Default = {action = "Inspect", wait = 1.0,
	log = function() return "Checked and left in order." end}

function K.forKind(kind) return K.Actions[kind] or K.Default end

return K
