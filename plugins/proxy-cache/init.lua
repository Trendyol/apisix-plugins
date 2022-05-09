local memory_handler = require("apisix.plugins.proxy-cache.memory_handler")
local disk_handler = require("apisix.plugins.proxy-cache.disk_handler")
local redis_handler = require("apisix.plugins.proxy-cache.redis_handler")
local util = require("apisix.plugins.proxy-cache.util")
local core = require("apisix.core")
local ipairs = ipairs

local plugin_name = "proxy-cache"

local STRATEGY_DISK = "disk"
local STRATEGY_MEMORY = "memory"
local STRATEGY_REDIS = "redis"


local policy_to_additional_properties = {
    redis = {
        properties = {
            redis_host = {
                type = "string", minLength = 2
            },
            redis_port = {
                type = "integer", minimum = 1, default = 6379,
            },
            redis_password = {
                type = "string", minLength = 0,
            },
            redis_database = {
                type = "integer", minimum = 0, default = 0,
            },
            redis_timeout = {
                type = "integer", minimum = 1, default = 1000,
            },
        },
       required = {"redis_host"},
    }
}

local schema = {
    type = "object",
    properties = {
        cache_zone = {
            type = "string",
            minLength = 1,
            maxLength = 100,
            default = "disk_cache_one",
        },
        cache_strategy = {
            type = "string",
            enum = {STRATEGY_DISK, STRATEGY_MEMORY, STRATEGY_REDIS},
            default = STRATEGY_DISK,
        },
        cache_key = {
            type = "array",
            minItems = 1,
            items = {
                description = "a key for caching",
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]],
            },
            default = {"$host", "$request_uri"}
        },
        cache_http_status = {
            type = "array",
            minItems = 1,
            items = {
                description = "http response status",
                type = "integer",
                minimum = 200,
                maximum = 599,
            },
            uniqueItems = true,
            default = {200, 301, 404},
        },
        cache_method = {
            type = "array",
            minItems = 1,
            items = {
                description = "supported http method",
                type = "string",
                enum = {"GET", "POST", "HEAD"},
            },
            uniqueItems = true,
            default = {"GET", "HEAD"},
        },
        hide_cache_headers = {
            type = "boolean",
            default = false,
        },
        cache_control = {
            type = "boolean",
            default = false,
        },
        cache_bypass = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]]
            },
        },
        no_cache = {
            type = "array",
            minItems = 1,
            items = {
                type = "string",
                pattern = [[(^[^\$].+$|^\$[0-9a-zA-Z_]+$)]]
            },
        },
        cache_ttl = {
            type = "integer",
            minimum = 1,
            default = 300,
        },
    },
    ["if"] = {
        properties = {
            cache_strategy = {
                enum = {"redis"},
            },
        },
    },
    ["then"] = policy_to_additional_properties.redis,
}


local _M = {
    version = 0.2,
    priority = 1009,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    for _, key in ipairs(conf.cache_key) do
        if key == "$request_method" then
            return false, "cache_key variable " .. key .. " unsupported"
        end
    end

    local found = false
    local local_conf = core.config.local_conf()
    if local_conf.apisix.proxy_cache then
        for _, cache in ipairs(local_conf.apisix.proxy_cache.zones) do
            if cache.name == conf.cache_zone then
                found = true
            end
        end

        if found == false then
            return false, "cache_zone " .. conf.cache_zone .. " not found"
        end
    end

    return true
end


function _M.access(conf, ctx)
    core.log.info("proxy-cache plugin access phase, conf: ", core.json.delay_encode(conf))

    local value = util.generate_complex_value(conf.cache_key, ctx)
    ctx.var.upstream_cache_key = value
    core.log.info("proxy-cache cache key value:", value)

    local handler
    if conf.cache_strategy == STRATEGY_MEMORY then
        handler = memory_handler
    elseif conf.cache_strategy == STRATEGY_DISK then
        handler = disk_handler
    elseif conf.cache_strategy == STRATEGY_REDIS then
        handler = redis_handler
    end

    return handler.access(conf, ctx)
end


function _M.header_filter(conf, ctx)
    core.log.info("proxy-cache plugin header filter phase, conf: ", core.json.delay_encode(conf))

    local handler
    if conf.cache_strategy == STRATEGY_MEMORY then
        handler = memory_handler
    elseif conf.cache_strategy == STRATEGY_DISK then
        handler = disk_handler
    elseif conf.cache_strategy == STRATEGY_REDIS then
        handler = redis_handler
    end

    handler.header_filter(conf, ctx)
end


function _M.body_filter(conf, ctx)
    core.log.info("proxy-cache plugin body filter phase, conf: ", core.json.delay_encode(conf))

    if conf.cache_strategy == STRATEGY_MEMORY then
        memory_handler.body_filter(conf, ctx)
    elseif conf.cache_strategy == STRATEGY_REDIS then
        redis_handler.body_filter(conf, ctx)
    end
end

return _M
