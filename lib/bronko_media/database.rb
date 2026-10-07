# frozen_string_literal: true

module BronkoMedia
  module Database
    def self.options(settings, environment: ENV.fetch('RACK_ENV', nil))
      if settings.db_adapter == 'sqlite3'
        return { adapter: 'sqlite3', database: settings.db_name, pool: settings.db_pool, timeout: 5000 }
      end

      {
        adapter: settings.db_adapter,
        database: settings.db_name,
        password: settings.db_password,
        username: settings.db_username,
        host: environment == 'development' ? 'localhost' : settings.db_host,
        encoding: settings.db_ecnoding,
        collation: settings.db_collation,
        pool: settings.db_pool
      }
    end
  end
end
