--[[
--	NEORG MODULE MANAGER
--	This file is responsible for loading, unloading, calling and managing modules
--	Modules are internal mini-programs that execute on certain events, they build the foundation of neorg itself.
--]]

-- Include the global logger instance
local log = require('neorg.external.log')

require('neorg.modules.base')

--[[
--	The reason we do not just call this variable neorg.modules.loaded_modules.count is because
--	someone could make a module called "count" and override the variable, causing bugs.
--]]
neorg.modules.loaded_module_count = 0

-- The table of currently loaded modules
neorg.modules.loaded_modules = {}

-- @Summary Load and enables a module
-- @Description Loads a specified module. If the module subscribes to any events then they will be activated too.
-- @Param  module (table) - the actual module to load
function neorg.modules.load_module_from_table(module)

	log.info("Loading module with name", module.name)

	-- If our module is already loaded don"t try loading it again
	if neorg.modules.loaded_modules[module.name] then
		log.warn("Module", module.name, "already loaded. Omitting...")
		return false
	end

	-- module.setup() will soon return more than just a success variable, eventually we"d like modules to expose metadata about themselves too
	local loaded_module = module.setup()

	-- We do not expect module.setup() to ever return nil, that"s why this check is in place
	if not loaded_module then
		log.error("Module", module.name, "does not handle module loading correctly; module.load() returned nil. Omitting...")
		return false
	end

	-- A part of the table returned by module.setup() tells us whether or not the module initialization was successful
	if loaded_module.success == false then
		log.info("Module", module.name, "did not load.")
		return false
	end

	-- Add the module into the list of loaded modules
	-- The reason we do this here is so other modules don't recursively require each other in the dependency loading loop below
	neorg.modules.loaded_modules[module.name] = module

	-- If any dependencies have been defined, handle them
	if loaded_module.requires and vim.tbl_count(loaded_module.requires) > 0 then

		log.info("Module", module.name, "has dependencies. Loading dependencies first...")

		-- Loop through each dependency and load it one by one
		for _, required_module in pairs(loaded_module.requires) do

			log.trace("Loading submodule", required_module)

			-- This would've always returned false had we not added the current module to the loaded module list earlier above
			if not neorg.modules.is_module_loaded(required_module) then
				if not neorg.modules.load_module(required_module) then
					log.error(("Unable to load module %s, required dependency %s did not load successfully"):format(module.name, required_module))

					-- Make sure to clean up after ourselves if the module failed to load
					neorg.modules.loaded_modules[module.name] = nil
					return false
				end
			else
				log.trace("Module", required_module, "already loaded, skipping...")
			end

			-- Create a reference to the dependency's public table
			module.required[required_module] = neorg.modules.loaded_modules[required_module].public

		end

	end

	log.info("Successfully loaded module", module.name)

	-- Keep track of the number of loaded modules
	neorg.modules.loaded_module_count = neorg.modules.loaded_module_count + 1

	-- Call the load function
	module.load()

	return true

end

-- @Summary Loads a module from disk
-- @Description Unlike load_module_from_table(), which loads a module from memory, load_module() tries to find the corresponding module file on disk and loads it into memory.
-- If the module could not be found, attempt to load it off of github. This function also applies user-defined configurations and keymaps to the modules themselves.
-- This is the recommended way of loading modules - load_module_from_table() should only really be used by neorg itself.
-- @Param  module_name (string) - a path to a module on disk. A path seperator in neorg is '.', not '/'
-- @Param  shortened_git_address (string) - for example "Vhyrro/neorg", tells neorg where to look on github if a module can't be found locally
-- @Param  config (table) - a configuration that reflects the structure of neorg.configuration.user_configuration.load["module.name"].config
function neorg.modules.load_module(module_name, shortened_git_address, config)

	-- Don't bother loading the module from disk if it's already loaded
	if neorg.modules.is_module_loaded(module_name) then
		return false
	end

	-- Attempt to require the module, does not throw an error if the module doesn't exist
	local exists, module

	-- (vim.schedule_wrap(function()
	exists, module = pcall(require, "neorg.modules." .. module_name .. ".module")
	-- end))()

	-- If the module can't be found, try looking for it on GitHub (currently unimplemented :P)
	if not exists then

		log.warn(("Unable to load module %s - an error occured: %s"):format(module_name, module))

		if shortened_git_address then
			-- If module isn"t found, grab it from the internet here
			return false
		end

		return false
	end

	-- If the module is nil for some reason return false
	if not module then return false end

	-- Load the user-defined configurations and keymaps
	if config and not vim.tbl_isempty(config) then
		module.config.public = vim.tbl_deep_extend("force", module.config.public, config)
	end

	-- Pass execution onto load_module_from_table() and let it handle the rest
	return neorg.modules.load_module_from_table(module)

end

-- @Summary Unloads a module by name
-- @Description Removes all hooks, all event subscriptions and unloads the module from memory
-- @Param module_name (string) - the name of the module to unload
function neorg.modules.unload_module(module_name)

	-- Check if the module is loaded
	local module = neorg.modules.loaded_modules[module_name]

	-- If not then obviously there's no point in unloading it
	if not module then
		log.info("Unable to unload module", module_name, "- module is not currently loaded.")
		return false
	end

	module.unload()

	-- Remove the module from the loaded_modules list and decrement the counter
	neorg.modules.loaded_modules[module_name] = nil
	neorg.modules.loaded_module_count = neorg.modules.loaded_module_count - 1

	return true
end

-- @Summary Gets the public API of a module by name
-- @Description Retrieves the public API exposed by the module
-- @Param  module_name (string) - the name of the module to retrieve
function neorg.modules.get_module(module_name)

	if not neorg.modules.is_module_loaded(module_name) then
		log.info("Attempt to get module with name", module_name, "failed.")
		return nil
	end

	return neorg.modules.loaded_modules[module_name].public
end

-- @Summary Retrieves the public configuration of a module
-- @Description Returns the module.config.public table if the module is loaded
-- @Param  module_name (string) - the name of the module to retrieve (module must be loaded)
function neorg.modules.get_module_config(module_name)

	if not neorg.modules.is_module_loaded(module_name) then
		log.info("Attempt to get module configuration with name", module_name, "failed.")
		return nil
	end

	return neorg.modules.loaded_modules[module_name].config.public
end

-- @Summary Check whether a module is loaded
-- @Description Returns true if module with name module_name is loaded, false otherwise
-- @Param  module_name (string) - the name of an arbitrary module
function neorg.modules.is_module_loaded(module_name)
	return neorg.modules.loaded_modules[module_name] ~= nil
end