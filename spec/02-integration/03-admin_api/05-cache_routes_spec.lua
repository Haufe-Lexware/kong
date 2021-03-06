local helpers = require "spec.helpers"
local cjson = require "cjson"

local current_cache
local caches = { "lua", "shm" }
local function do_it(desc, func)
  for _, cache in ipairs(caches) do
    it("[cache="..cache.."] "..desc,
      function(...)
        current_cache = cache
        return func(...)
      end)
  end
end

describe("Admin API", function()
  local client, proxy_client
  setup(function()
    assert(helpers.start_kong({
      custom_plugins = "first-request",
      lua_package_path = "?/init.lua;./kong/?.lua;./spec/fixtures/?.lua"
    }))
    client = helpers.admin_client()
    proxy_client = helpers.proxy_client(2000)
  end)
  teardown(function()
    if client then
      client:close()
      proxy_client:close()
    end
    helpers.stop_kong()
  end)

  describe("/cache/{key}", function()
    setup(function()
      assert(helpers.dao.apis:insert {
        name = "api-cache",
        hosts = { "cache.com" },
        upstream_url = "http://mockbin.com"
      })
      local res = assert(client:send {
        method = "POST",
        path = "/apis/api-cache/plugins/",
        headers = {
          ["Content-Type"] = "application/json"
        },
        body = {
          name = "first-request"
        }
      })
      assert.res_status(201, res)
    end)

    describe("GET", function()
      do_it("returns 404 if not found", function()
        local res = assert(client:send {
          method = "GET",
          path = "/cache/_inexistent_",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(404)
      end)
      it("retrieves a cached entity", function()
        -- populate cache
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {host = "cache.com"},
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)

        res = assert(client:send {
          method = "GET",
          path = "/cache/requested",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        if current_cache == "shm" then
          -- in this case the entry is jsonified (string type) and hence send as a "message" entry
          json = cjson.decode(json.message)
        end
        assert.True(json.requested)
      end)
    end)

    describe("DELETE", function()
      it("purges cached entity", function()
        -- populate cache
        local res = assert(proxy_client:send {
          method = "GET",
          path = "/",
          headers = {host = "cache.com"},
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)

        res = assert(client:send {
          method = "GET",
          path = "/cache/requested",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(200)

        -- delete cache
        res = assert(client:send {
          method = "DELETE",
          path = "/cache/requested",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(204)

        res = assert(client:send {
          method = "GET",
          path = "/cache/requested",
          query = { cache = current_cache },
        })
        assert.response(res).has.status(404)
      end)
    end)

    describe("/cache/", function()
      describe("DELETE", function()
        it("purges all entities", function()
           -- populate cache
          local res = assert(proxy_client:send {
            method = "GET",
            path = "/",
            headers = {host = "cache.com"},
            query = { cache = current_cache },
          })
          assert.response(res).has.status(200)

          res = assert(client:send {
            method = "GET",
            path = "/cache/requested",
            query = { cache = current_cache },
          })
          assert.response(res).has.status(200)

           -- delete cache
          res = assert(client:send {
            method = "DELETE",
            path = "/cache",
            query = { cache = current_cache },
          })
          assert.response(res).has.status(204)

          res = assert(client:send {
            method = "GET",
            path = "/cache/requested",
            query = { cache = current_cache },
          })
          assert.response(res).has.status(404)
        end)
      end)
    end)
  end)
end)
