local ngx = ngx
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local upstream = require("apisix.upstream")
local mlcache = require "resty.mlcache"

local schema = {
    type = "object",
    properties = {
        uri = {type = "string"},
        srcip_header = {type = "string" },
    },
    required = {"uri"},
}

local plugin_name = "ty-geoip-plugin"

local _M = {
    version = 0.1,
    priority = -9000,
    name = plugin_name,
    schema = schema,
}


-- we need to initialize the cache on the lua module level so that
-- it can be shared by all the requests served by each nginx worker process:
-- local cache = lrucache.new(10000)  -- allow up to 10000 items in the cache

local cache, err = mlcache.new("geoip_cache", "geoip_cache_shared_dict", {
    lru_size = 1000, -- hold up to 1000 items in the L1 cache (Lua VM)
    ttl      = 60, -- caches scalar types and tables for 1m
})
if not cache then
    error("could not create mlcache: " .. err)
end

function _M.check_schema(conf, schema_type)
    return core.schema.check(schema, conf)
end

function _M.init()
    -- call this function when plugin is loaded
    local attr = plugin.plugin_attr(plugin_name)
    if attr then
        core.log.warn(plugin_name, " get plugin attr val: ", attr.val)
    end
end


function _M.destroy()
    -- call this function when plugin is unloaded
end
local function query_geoip(remote_addr ,conf)
    local http = require("resty.http").new()
    local cjson = require("cjson")
    local country_code
    http:set_timeout(100)
    local res, err = http:request_uri(conf.uri .. remote_addr)
    if not err then
        if res.status == 200 then
            if cjson.decode(res.body)["country"]["iso_code"] == nil then
                country_code = "XX"
            else
                country_code = cjson.decode(res.body)["country"]["iso_code"]
            end
        else
            country_code = "XX"
        end
    else
        country_code = "XX"
    end
    if country_code == "XX" then
        return country_code,nil,-1
    else
        return country_code
    end
end

function _M.rewrite(conf, ctx)
    local remote_addr
    if conf.srcip_header then
        remote_addr = core.request.header(ctx, conf.srcip_header)
    end
    if remote_addr == nil then
        core.log.error(plugin_name, " Param ".. conf.srcip_header .. " not found in request header. Failing back to original source IP ")
        remote_addr = ctx.var.remote_addr
    end

    local country_code, err, hit_level = cache:get(remote_addr, nil, query_geoip, remote_addr, conf)
    core.log.debug(plugin_name, " cache_hit_level: ", hit_level)
    core.request.set_header(ctx, "TY-country", country_code)
end


return _M
