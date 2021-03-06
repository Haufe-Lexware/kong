return {
  {
    name = "2015-01-12-175310_skeleton",
    up = function(db, properties)
      return db:queries [[
        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations varchar(100)[]
        );
      ]]
    end,
    down = [[
      DROP TABLE schema_migrations;
    ]]
  },
  {
    name = "2015-01-12-175310_init_schema",
    up = [[
      CREATE TABLE IF NOT EXISTS consumers(
        id uuid PRIMARY KEY,
        custom_id text,
        username text UNIQUE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('custom_id_idx')) IS NULL THEN
          CREATE INDEX custom_id_idx ON consumers(custom_id);
        END IF;
        IF (SELECT to_regclass('username_idx')) IS NULL THEN
          CREATE INDEX username_idx ON consumers((lower(username)));
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS apis(
        id uuid PRIMARY KEY,
        name text UNIQUE,
        request_host text UNIQUE,
        request_path text UNIQUE,
        strip_request_path boolean NOT NULL,
        upstream_url text,
        preserve_host boolean NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('apis_name_idx')) IS NULL THEN
          CREATE INDEX apis_name_idx ON apis(name);
        END IF;
        IF (SELECT to_regclass('apis_request_host_idx')) IS NULL THEN
          CREATE INDEX apis_request_host_idx ON apis(request_host);
        END IF;
        IF (SELECT to_regclass('apis_request_path_idx')) IS NULL THEN
          CREATE INDEX apis_request_path_idx ON apis(request_path);
        END IF;
      END$$;



      CREATE TABLE IF NOT EXISTS plugins(
        id uuid,
        name text NOT NULL,
        api_id uuid REFERENCES apis(id) ON DELETE CASCADE,
        consumer_id uuid REFERENCES consumers(id) ON DELETE CASCADE,
        config json NOT NULL,
        enabled boolean NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (id, name)
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('plugins_name_idx')) IS NULL THEN
          CREATE INDEX plugins_name_idx ON plugins(name);
        END IF;
        IF (SELECT to_regclass('plugins_api_idx')) IS NULL THEN
          CREATE INDEX plugins_api_idx ON plugins(api_id);
        END IF;
        IF (SELECT to_regclass('plugins_consumer_idx')) IS NULL THEN
          CREATE INDEX plugins_consumer_idx ON plugins(consumer_id);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE consumers;
      DROP TABLE apis;
      DROP TABLE plugins;
    ]]
  },
  {
    name = "2015-11-23-817313_nodes",
    up = [[
      CREATE TABLE IF NOT EXISTS nodes(
        name text,
        cluster_listening_address text,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc'),
        PRIMARY KEY (name)
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('nodes_cluster_listening_address_idx')) IS NULL THEN
          CREATE INDEX nodes_cluster_listening_address_idx ON nodes(cluster_listening_address);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE nodes;
    ]]
  },
  {
    name = "2016-02-29-142793_ttls",
    up = [[
      CREATE TABLE IF NOT EXISTS ttls(
        primary_key_value text NOT NULL,
        primary_uuid_value uuid,
        table_name text NOT NULL,
        primary_key_name text NOT NULL,
        expire_at timestamp without time zone NOT NULL,
        PRIMARY KEY(primary_key_value, table_name)
      );

      CREATE OR REPLACE FUNCTION upsert_ttl(v_primary_key_value text, v_primary_uuid_value uuid, v_primary_key_name text, v_table_name text, v_expire_at timestamp) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE ttls SET expire_at = v_expire_at WHERE primary_key_value = v_primary_key_value AND table_name = v_table_name;
          IF found then
            RETURN;
          END IF;
          BEGIN
            INSERT INTO ttls(primary_key_value, primary_uuid_value, primary_key_name, table_name, expire_at) VALUES(v_primary_key_value, v_primary_uuid_value, v_primary_key_name, v_table_name, v_expire_at);
            RETURN;
          EXCEPTION WHEN unique_violation THEN
            -- Do nothing, and loop to try the UPDATE again.
          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    down = [[
      DROP TABLE ttls;
      DROP FUNCTION upsert_ttl(text, uuid, text, text, timestamp);
    ]]
  },
  {
    name = "2016-09-05-212515_retries",
    up = [[
      DO $$
      BEGIN
        ALTER TABLE apis ADD COLUMN retries smallint NOT NULL DEFAULT 5;
      EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
      END$$;
    ]],
    down = [[
      ALTER TABLE apis DROP COLUMN IF EXISTS retries;
    ]]
  },
  {
    name = "2016-09-16-141423_upstreams",
    -- Note on the timestamps below; these use a precision of milliseconds
    -- this differs from the other tables above, as they only use second precision.
    -- This differs from the change to the Cassandra entities.
    up = [[
      CREATE TABLE IF NOT EXISTS upstreams(
        id uuid PRIMARY KEY,
        name text UNIQUE,
        slots int NOT NULL,
        orderlist text NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(3) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('upstreams_name_idx')) IS NULL THEN
          CREATE INDEX upstreams_name_idx ON upstreams(name);
        END IF;
      END$$;
      CREATE TABLE IF NOT EXISTS targets(
        id uuid PRIMARY KEY,
        target text NOT NULL,
        weight int NOT NULL,
        upstream_id uuid REFERENCES upstreams(id) ON DELETE CASCADE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(3) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('targets_target_idx')) IS NULL THEN
          CREATE INDEX targets_target_idx ON targets(target);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE upstreams;
      DROP TABLE targets;
    ]],
  },
  {
    name = "2016-12-14-172100_move_ssl_certs_to_core",
    up = [[
      CREATE TABLE ssl_certificates(
        id uuid PRIMARY KEY,
        cert text ,
        key text ,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      CREATE TABLE ssl_servers_names(
        name text PRIMARY KEY,
        ssl_certificate_id uuid REFERENCES ssl_certificates(id) ON DELETE CASCADE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(0) at time zone 'utc')
      );

      ALTER TABLE apis ADD https_only boolean;
      ALTER TABLE apis ADD http_if_terminated boolean;
    ]],
    down = [[
      DROP TABLE ssl_certificates;
      DROP TABLE ssl_servers_names;

      ALTER TABLE apis DROP COLUMN IF EXISTS https_only;
      ALTER TABLE apis DROP COLUMN IF EXISTS http_if_terminated;
    ]]
  },
  {
    name = "2016-11-11-151900_new_apis_router_1",
    up = [[
      DO $$
      BEGIN
        ALTER TABLE apis ADD hosts text;
        ALTER TABLE apis ADD uris text;
        ALTER TABLE apis ADD methods text;
        ALTER TABLE apis ADD strip_uri boolean;
      EXCEPTION WHEN duplicate_column THEN

      END$$;
    ]],
    down = [[
      ALTER TABLE apis DROP COLUMN IF EXISTS headers;
      ALTER TABLE apis DROP COLUMN IF EXISTS uris;
      ALTER TABLE apis DROP COLUMN IF EXISTS methods;
      ALTER TABLE apis DROP COLUMN IF EXISTS strip_uri;
    ]]
  },
  {
    name = "2016-11-11-151900_new_apis_router_2",
    up = function(_, _, dao)
      -- create request_headers and request_uris
      -- with one entry each: the current request_host
      -- and the current request_path
      -- We use a raw SQL query because we removed the
      -- request_host/request_path fields in the API schema,
      -- hence the Postgres DAO won't include them in the
      -- retrieved rows.
      local rows, err = dao.db:query([[
        SELECT * FROM apis;
      ]])
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        local fields_to_update = {
          hosts = { row.request_host },
          uris = { row.request_path },
          strip_uri = row.strip_request_path,
        }

        local _, err = dao.apis:update(fields_to_update, { id = row.id })
        if err then
          return err
        end
      end
    end,
    down = function(_, _, dao)
      -- re insert request_host and request_path from
      -- the first element of request_headers and
      -- request_uris

    end
  },
  {
    name = "2016-11-11-151900_new_apis_router_3",
    up = [[
      DROP INDEX IF EXISTS apis_request_host_idx;
      DROP INDEX IF EXISTS apis_request_path_idx;

      ALTER TABLE apis DROP COLUMN IF EXISTS request_host;
      ALTER TABLE apis DROP COLUMN IF EXISTS request_path;
      ALTER TABLE apis DROP COLUMN IF EXISTS strip_request_path;
    ]],
    down = [[
      ALTER TABLE apis ADD request_host text;
      ALTER TABLE apis ADD request_path text;
      ALTER TABLE apis ADD strip_request_path boolean;

      CREATE INDEX IF NOT EXISTS ON apis(request_host);
      CREATE INDEX IF NOT EXISTS ON apis(request_path);
    ]]
  },
  {
    name = "2016-09-16-141423_upstreams",
    -- Note on the timestamps below; these use a precision of milliseconds
    -- this differs from the other tables above, as they only use second precision.
    -- This differs from the change to the Cassandra entities.
    up = [[
      CREATE TABLE IF NOT EXISTS upstreams(
        id uuid PRIMARY KEY,
        name text UNIQUE,
        slots int NOT NULL,
        orderlist text NOT NULL,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(3) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('upstreams_name_idx')) IS NULL THEN
          CREATE INDEX upstreams_name_idx ON upstreams(name);
        END IF;
      END$$;
      CREATE TABLE IF NOT EXISTS targets(
        id uuid PRIMARY KEY,
        target text NOT NULL,
        weight int NOT NULL,
        upstream_id uuid REFERENCES upstreams(id) ON DELETE CASCADE,
        created_at timestamp without time zone default (CURRENT_TIMESTAMP(3) at time zone 'utc')
      );
      DO $$
      BEGIN
        IF (SELECT to_regclass('targets_target_idx')) IS NULL THEN
          CREATE INDEX targets_target_idx ON targets(target);
        END IF;
      END$$;
    ]],
    down = [[
      DROP TABLE upstreams;
      DROP TABLE targets;
    ]],
  },
}
