--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local ngx = ngx
local ngx_shared = ngx.shared
local setmetatable = setmetatable
local core = require("apisix.core")
local redis_new = require("resty.redis").new
local red = redis_new()
local timeout = 1000    -- 1sec

-- core.log.info("ttl key: ", key, " timeout: ", timeout)
-- red:set_timeouts(timeout, timeout, timeout)

-- local ok, err = red:connect("192.168.44.100", 6379)
-- if not ok then
--     return false, err
-- end


local _M = {}


function _M.new(opts)
    local redis_opts = {}
    -- use a special pool name only if database is set to non-zero
    -- otherwise use the default pool name host:port
    redis_opts.pool = opts.redis_database and opts.redis_host .. ":" .. opts.redis_port .. ":" .. opts.redis_database

    red:set_timeout(opts.redis_timeout)

    -- conecto
    local ok, err = red:connect(opts.redis_host, opts.redis_port, redis_opts)
    if not ok and not string.find(err, "connected") then
        core.log.warn(core.json.encode(opts))
        core.log.warn("1- failed to connect to Redis: ", opts.redis_host)
        core.log.warn("1- failed to connect to Redis: ", err)
        return nil, err
    end

    local times, err2 = red:get_reused_times()
    if err2 then
        core.log.warn("2- failed to get connect reused times: ", err2)
        return nil, err
    end

    if times == 1 then
        if is_present(opts.redis_password) then
            local ok3, err3 = red:auth(opts.redis_password)
            if not ok3 then
                core.log.warn("3- failed to auth Redis: ", err3)
                return nil, err
            end
        end

        if opts.redis_database ~= 0 then
            -- Only call select first time, since we know the connection is shared
            -- between instances that use the same redis database
            local ok4, err4 = red:select(opts.redis_database)
            if not ok4 then
                core.log.warn("4- failed to change Redis database: ", err4)
                return nil, err
            end
        end
    end
    return red
end


function _M:set(key, obj)
    local obj_json = core.json.encode(obj)
    if not obj_json then
        return nil, "could not encode object"
    end

    local succ, err = red:set(key, obj_json, "EX", obj.ttl)
    return succ and obj_json or nil, err
end


function _M:get(key)
    -- If the key does not exist or has expired, then res_json will be nil.
    local res_json, err = red:get(key)
    if err then
        return nil, err
    end
    core.log.warn("get key: ", key, " res_json: ", res_json)

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
    local purge, err = red:del(key)
    if not purge then
        return nil, err
    end
end


return _M
