# frozen_string_literal: true

module BronkoMedia
  module Database
    def self.options(settings, environment: ENV.fetch('RACK_ENV', nil))
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
