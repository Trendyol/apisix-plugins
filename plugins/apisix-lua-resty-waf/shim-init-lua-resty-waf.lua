local ngx = ngx
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local lua_resty_waf = require("resty.waf")

local plugin_name = "shim-init-lua-resty-waf"
local schema = {
    type = "object",
    properties = {
        dummysetting = {
            type = "string",
            default = "dummy"
        }
    }
}

local _M = {
    version = 0.1,
    priority = -9999,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end


function _M.destroy()
    -- call this function when plugin is unloaded
end

function _M.init()
    -- call this function when plugin is loaded
    local attr = plugin.plugin_attr(plugin_name)
    if attr then
        core.log.info(plugin_name, " get plugin attr val: ", attr.val)
    end

    lua_resty_waf.init()
end

return _M