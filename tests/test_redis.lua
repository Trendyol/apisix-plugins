local mock_calls = { new = 0, connect = 0, set_keepalive = 0 }
local mock_red = {
    connect = function() return true end,
    auth = function() return true end,
    select = function() return true end,
    get = function() return nil, "not found" end,
    set_timeout = function() end,
    get_reused_times = function() return 0, nil end,
    set_keepalive = function()
        mock_calls.set_keepalive = mock_calls.set_keepalive + 1
        return true
    end,
    -- track calls
    calls = mock_calls
}

-- Mocks
package.loaded["resty.redis"] = {
    new = function()
        mock_red.calls.new = mock_red.calls.new + 1
        return mock_red
    end
}

package.loaded["apisix.core"] = {
    log = {
        info = function(...) print("INFO:", ...) end,
        warn = function(...) print("WARN:", ...) end,
        error = function(...) print("ERROR:", ...) end
    },
    json = {
        delay_encode = function(t) return t end,
        encode = function(t) return "{}" end,
        decode = function(s) return {} end
    },
    response = {
        set_header = function(...) end
    },
    table = {
        clear = function() end
    }
}

package.loaded["apisix.plugins.proxy-cache-distributed.util"] = {
    match_method = function() return true end,
    match_status = function() return true end,
    generate_complex_value = function() return "key" end
}

-- Mock table.new
package.loaded["table.new"] = function(narr, nrec) return {} end

-- Global ngx mock
_G.ngx = {
    now = function() return 1 end,
    re = {
        gmatch = function() return function() return nil end end,
        match = function() return nil end
    },
    parse_http_time = function() return nil end,
    shared = {
        memory_cache = { get = function() return nil end, set = function() end }
    },
    var = {
        http_cache_control = "",
        request_method = "GET",
        upstream_cache_key = "key"
    }
}

-- Test
local redis_handler = require("plugins.proxy-cache-distributed.redis_handler")
local conf = {
    redis_host = "127.0.0.1",
    redis_port = 6379,
    redis_timeout = 1000,
    redis_database = 0
}
local ctx = { var = _G.ngx.var, cache = {} }

print("Running access phase 1...")
redis_handler.access(conf, ctx)

print("Running access phase 2...")
redis_handler.access(conf, ctx)

-- Assertions
print("Verifying results...")
if mock_red.calls.new == 2 then
    print("PASS: redis.new() called twice (connection per request)")
else
    print("FAIL: redis.new() called " .. mock_red.calls.new .. " times")
    os.exit(1)
end

if mock_red.calls.set_keepalive >= 2 then
    print("PASS: set_keepalive called implementation " .. mock_red.calls.set_keepalive .. " times")
else
    print("FAIL: set_keepalive NOT called enough times (count: " .. mock_red.calls.set_keepalive .. ")")
    os.exit(1)
end

-- Test 3: Complex Cache-Control
print("Test 3: Complex Cache-Control")
_G.ngx.var.http_cache_control = "private, max-age=300, no-transform"
redis_handler.access(conf, ctx)
-- If it doesn't crash, we assume success for now as we don't inspect internal state easily
print("PASS: Handled complex Cache-Control without crash")
