local mock_http_new = {
    set_timeout = function() end,
    request_uri = function(self, uri)
        if string.find(uri, "bad_json") then
            return { status = 200, body = "invalid json { " }, nil
        else
            return { status = 200, body = '{"country": {"iso_code": "US"}}' }, nil
        end
    end
}

package.loaded["resty.http"] = {
    new = function() return mock_http_new end
}

package.loaded["cjson"] = {
    decode = function(s)
        if string.find(s, "invalid") then
            error("Expected value but found invalid token at character 1")
        end
        return { country = { iso_code = "US" } }
    end
}

package.loaded["apisix.core"] = {
    log = {
        warn = function(...) print("WARN:", ...) end,
        error = function(...) print("ERROR (Expected):", ...) end,
        debug = function(...) end
    },
    schema = { check = function() return true end },
    request = {
        set_header = function(ctx, k, v)
            print("SET HEADER: " .. k .. "=" .. tostring(v))
        end,
        header = function() return nil end
    }
}
package.loaded["apisix.plugin"] = {
    plugin_attr = function() return nil end
}
package.loaded["apisix.upstream"] = {}
package.loaded["resty.mlcache"] = {
    new = function() return { get = function(self, key, opts, cb, ...) return cb(...) end } end
}

_G.ngx = {
    re = { sub = function() end, gmatch = function() end },
    var = { remote_addr = "1.2.3.4" }
}

local geoip = require("plugins.ty-geoip-plugin.ty-geoip-plugin")

-- Test 1: Good JSON
local code = geoip.check_schema({ uri = "http://test/" })

print("Test 1: Valid JSON")
local code, err = geoip.rewrite({ uri = "http://test/", srcip_header = "X-IP" }, { var = { remote_addr = "1.2.3.4" } })

-- Test 2: Bad JSON
print("Test 2: Invalid JSON")
local mock_conf = { uri = "http://test/bad_json", srcip_header = "X-IP" }

local status, err = pcall(function()
    geoip.rewrite(mock_conf, { var = { remote_addr = "1.2.3.4" } })
end)

if status then
    print("PASS: Did not crash on invalid JSON")
else
    print("FAIL: Crashed on invalid JSON: " .. tostring(err))
    os.exit(1)
end
