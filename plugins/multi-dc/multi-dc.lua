local core      = require("apisix.core")
local upstream  = require("apisix.upstream")
local re_sub    = ngx.re.sub
local re_gmatch = ngx.re.gmatch

local UPSTREAM_SOURCE = {
    SERVICE = "service",
    DATA_CENTER = "data_center"
}

local id_schema = {
    anyOf = {
        {
            type = "string", minLength = 1, maxLength = 64,
            pattern = [[^[a-zA-Z0-9-_.]+$]]
        },
        { type = "integer", minimum = 1 }
    }
}

local services_schema = {
    type = "object",
    patternProperties = {
        [".*"] = {
            description = "service items",
            type = "object",
            properties = {
                upstream_id = id_schema,
            },
            required = {"upstream_id"},
            minimum = 1,
        },
    },
    additionalProperties = false,
}

local data_centers_schema = {
    type = "object",
    patternProperties = {
        [".*"] = {
            description = "data center items",
            type = "object",
            properties = {
                services = services_schema,
                upstream_id = id_schema,
            },
            anyOf = {
                {required = {"services", "upstream_id"}},
                {required = {"services"}},
                {required = {"upstream_id"}}
            },
            minimum = 1,
        },
    },
    additionalProperties = false,
}

local schema = {
    type = "object",
    properties = {
        data_centers = data_centers_schema,
    },
    required = {"data_centers"}
}


local _M = {
    version = 0.1,
    priority = 967,
    name = "multi-dc",
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function set_upstream(upstream_info, ctx)
    local up_conf = {
        name = upstream_info.name,
        type = upstream_info.type,
        hash_on = upstream_info.hash_on,
        pass_host = upstream_info.pass_host,
        upstream_host = upstream_info.upstream_host,
        key = upstream_info.key,
        nodes = upstream_info.nodes,
        timeout = upstream_info.timeout,
    }

    local ok, err = upstream.check_schema(up_conf)
    if not ok then
        core.log.error("failed to validate generated upstream: ", err)
        return 500, err
    end

    local matched_route = ctx.matched_route
    up_conf.parent = matched_route
    local upstream_key = up_conf.type .. "#route_" ..
                         matched_route.value.id .. "_multi-dc_" .. upstream_info.id
    core.log.info("upstream_key: ", upstream_key)
    upstream.set(ctx, upstream_key, ctx.conf_version, up_conf)

    return
end


function _M.access(conf, ctx)
    -- extract target data_center and service
    local segment = {}
    for str in re_gmatch(ctx.var.host, "([^.]+)") do
        table.insert(segment, str[1])
    end

    first_segment_arr = ngx_re.split(segment[1],"-")
    target_dci = first_segment_arr[#first_segment_arr]
    service_name = segment[1]:gsub("-" .. target_dci, '')
    target_dc = re_sub(target_dci, "^(.*)dci", "$1")
    -- check target
    if not segment[1] or not segment[2] then
        return 503, {error_msg = "incorrect target syntax"}
    end

    -- remove "-dci" suffix
    core.log.debug("try to access external service, data center: ",target_dc,
                    ", service: " .. service_name)
    newhost = service_name .. "." .. target_dc .. "." .. segment[3] .. "." .. segment[4]
    -- find target upstream
    local target_upstream_id, target_upstream_source
    local target_data_center = conf.data_centers[target_dc]

    if target_data_center ~= nil then
        if target_data_center.services ~= nil and
            target_data_center.services[service_name] ~= nil then
                target_upstream_id = target_data_center.services[service_name].upstream_id
                target_upstream_source = UPSTREAM_SOURCE.SERVICE
        end

        if target_upstream_id == nil and target_data_center.upstream_id ~= nil then
            target_upstream_id = target_data_center.upstream_id
            target_upstream_source = UPSTREAM_SOURCE.DATA_CENTER
        end
    end

    if not target_upstream_id then
        core.log.warn("cannot find target upstream")
        return 503, {error_msg = "no target upstream"}
    end

    -- dynamic set upstream
    core.log.debug("selected upstream id: ", target_upstream_id, ", source: ", target_upstream_source)
    local target_upstream = upstream.get_by_id(target_upstream_id)
    core.log.debug("upstream info: ", target_upstream)

    if not target_upstream then
        core.log.warn("target upstream not exist: ", target_upstream_id)
        return 503, {error_msg = "target upstream not exist"}
    end
    target_upstream.pass_host = "rewrite"
    target_upstream.upstream_host = newhost
    return set_upstream(target_upstream, ctx)
end


return _M
