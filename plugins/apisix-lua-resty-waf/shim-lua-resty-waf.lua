local ngx = ngx
local core = require("apisix.core")
local plugin = require("apisix.plugin")
local lua_resty_waf = require("resty.waf")

local log_levels = {
    info  = ngx.INFO,
    warn  = ngx.WARN,
    error = ngx.ERROR,
    debug = ngx.DEBUG
}

local plugin_name = "shim-lua-resty-waf"
local schema = {
    type = "object",
    properties = {
        mode = {
            type = "string",
            enum    = {"SIMULATE", "ACTIVE", "INACTIVE"}
            default = "INACTIVE"
        },
        client_score_threshold = {
            type = "integer",
            default = 5
        },
        debug_log_level = {
            type = "string",
            enum    = {"info", "warn", "error", "debug"}
            default = "info"
        },
        debug_enabled = {
            type = "boolean",
            default = false
        },
        extra_rules = {
            type = "array",
            minItems = 1,
            items = {
                description = "rule name, like 8000_demo_rule",
                type = "string",
            }
        },
    }
}


local _M = {
    version = 0.7,
    priority = -9900,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf, schema_type)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    
    return true
end


function _M.destroy()
    -- call this function when plugin is unloaded
end

function _M.access(conf, ctx)
    local waf = lua_resty_waf:new()

    waf:set_option("event_log_request_body", true)
    waf:set_option("event_log_request_headers", true)
    waf:set_option("debug", conf.debug_enabled)
    waf:set_option("mode", conf.mode)
    waf:set_option("debug_log_level", log_levels[conf.debug_log_level])
    waf:set_option("score_threshold", conf.client_score_threshold)
    waf:set_option("event_log_periodic_flush",30)
    waf:set_option("event_log_buffer_size", 128)
    waf:set_option("event_log_ngx_vars", "request_id")
    waf:set_option("event_log_ngx_vars", "server_port")
    waf:set_option("event_log_request_arguments", true)
    waf:set_option("allow_unknown_content_types", true)
    waf:set_option("event_log_target", "error")
    waf:set_option("process_multipart_body", true)
    waf:set_option("res_body_max_size", 1024 * 1024 * 2)
    waf:set_option("req_tid_header", false)
    waf:set_option("res_tid_header", false)
    waf:set_option("res_body_mime_types", {
        "text/plain",
        "text/html",
        "text/json",
        "application/json",
        "text/php",
        "text/plain",
        "text/x-php",
        "application/php",
        "application/x-php",
        "application/x-httpd-php",
        "application/x-httpd-php-source",
    })

    if conf.extra_rules and #conf.extra_rules > 0 then
        for _, extra_rule_name in pairs(conf.extra_rules) do
            waf:set_option("add_ruleset", extra_rule_name)
        end
    end

    local status, obj = waf:exec()
    return status, obj
end

function _M.header_filter(conf, ctx)
    local waf = lua_resty_waf:new()

    waf:exec()
end

function _M.body_filter(conf, ctx)
    local waf = lua_resty_waf:new()

    waf:exec()
end

function _M.log(conf, ctx)
    local waf = lua_resty_waf:new()

    waf:exec()
end

return _M

