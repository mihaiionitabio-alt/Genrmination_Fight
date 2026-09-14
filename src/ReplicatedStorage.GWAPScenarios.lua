-- Two assignments only, one per role, both long multi-floor runs.
-- The player never picks one: selecting a role assigns it.
-- Every named stop is a station Capability with three instances in the map
-- (one original, two backups), so a destroyed or unreachable station reroutes
-- to an equivalent rather than stalling the run.
return {
	{
		title='Germination integrity chain',
		role='Technician',
		purpose='Carry a viable seedling from the basement seed bank through orientation and vitality screening to the rooftop greenhouse.',
		route={'Seed bank','Incubator','Clinostat','Orientation scanner','Vitality scanner'},
		variable='Moisture', units='%', low=35, high=80,
	},
	{
		title='Cold-chain contamination audit',
		role='Laboratory Technician',
		purpose='Move a thawed sample through the wet lab and symbiosis line, clearing contamination checks before rooftop planting.',
		route={'Cryo-freezer','Wet lab','Symbiosis incubator','Chemical seedlings','Porometer'},
		variable='Recovery temperature', units='C', low=5, high=20,
	},
}
