local ngx = ngx
local ngx_shared = ngx.shared
local setmetatable = setmetatable
local core = require("apisix.core")

local _M = {}
local mt = { __index = _M }


function _M.new(opts)
    return setmetatable({
        dict = ngx_shared[opts.shdict_name],
    }, mt)
end


function _M:set(key, obj, ttl)
    local obj_json = core.json.encode(obj)
    if not obj_json then
        return nil, "could not encode object"
    end

    local succ, err = self.dict:set(key, obj_json, ttl)
    return succ and obj_json or nil, err
end


function _M:get(key)
    -- If the key does not exist or has expired, then res_json will be nil.
    local res_json, err = self.dict:get(key)
    if not res_json then
        if not err then
            return nil, "not found"
        else
            return nil, err
        end
    end

    local res_obj, err = core.json.decode(res_json)
    if not res_obj then
        return nil, err
    end

    return res_obj, nil
end


function _M:purge(key)
    self.dict:delete(key)
end


return _M
