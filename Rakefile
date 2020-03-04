require 'active_record'
require 'database_cleaner'
require 'factory_bot'
require 'yaml'
require 'yaml_db'

require_relative 'models.rb'
require_relative 'messages.rb'

module Rails
  def Rails.env
    DATABASE_ENV
  end
end

namespace :db do
  task :environment do
    DATABASE_ENV = ENV['DATABASE_ENV'] || 'development'
    MIGRATIONS_DIR = ENV['MIGRATIONS_DIR'] || 'db/migrate'
  end

  task :configuration => :environment do
    @config = YAML.load_file('db/config.yml')[DATABASE_ENV]
  end

  task :configure_connection => :configuration do
    ActiveRecord::Base.establish_connection(@config)
  end

  task :create => :configure_connection do
    ActiveRecord::Base.establish_connection(@config)
  end

  task :drop => :configure_connection do
    ActiveRecord::Base.connection.drop_database(@config['database'])
  end

  task :migrate => :configure_connection do
    require_relative 'models.rb'
    ActiveRecord::Migrator.migrate(MIGRATIONS_DIR, ENV['VERSION'] ? ENV['VERSION'].to_i : nil)
  end

  task :rollback => :configure_connection do
    ActiveRecord::Migrator.rollback(MIGRATIONS_DIR, (ENV['STEP'] || 1).to_i)
  end

  task :seed => :configure_connection do
    require_relative 'models.rb'
    require_relative 'db/seeds.rb'
  end

  task :test => :configure_connection do
    require 'test/unit'
    require 'test/unit/ui/console/testrunner'
    require 'mocha/test_unit'

    class Test::Unit::TestCase
      include FactoryBot::Syntax::Methods
    end

    FactoryBot.find_definitions

    require_relative 'test/test_models.rb'
    require_relative 'test/test_messages.rb'

    DatabaseCleaner.strategy = :transaction

    [TestScores, TestRankings, TestMessages].each do |suite|
      Test::Unit::UI::Console::TestRunner.run(suite)
    end
  end

  desc "Dump schema and data to db/schema.rb and db/data.yml"
  task(:dump => [ "db:schema:dump", "db:data:dump" ])

  desc "Load schema and data from db/schema.rb and db/data.yml"
  task(:load => [ "db:schema:load", "db:data:load" ])

  namespace :data do
    desc "Dump contents of database to db/data.extension (defaults to yaml)"
    task :dump => :environment do
      YamlDb::RakeTasks.data_dump_task
    end

    desc "Dump contents of database to curr_dir_name/tablename.extension (defaults to yaml)"
    task :dump_dir => :environment do
      YamlDb::RakeTasks.data_dump_dir_task
    end

    desc "Load contents of db/data.extension (defaults to yaml) into database"
    task :load => [:environment, :configure_connection] do
      YamlDb::RakeTasks.data_load_task
    end

    desc "Load contents of db/data_dir into database"
    task :load_dir  => :environment do
      YamlDb::RakeTasks.data_load_dir_task
    end
  end

  namespace :schema do
    desc "Creates a db/schema.rb file that is portable against any DB supported by Active Record"
    task dump: [:environment, :configure_connection] do
      require "active_record/schema_dumper"
      filename = ENV["SCHEMA"] || File.join(ActiveRecord::Tasks::DatabaseTasks.db_dir, "schema.rb")
      File.open(filename, "w:utf-8") do |file|
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
      end
      # db_namespace["schema:dump"].reenable
    end

    desc "Loads a schema.rb file into the database"
    task load: [:environment, :configure_connection] do
      ActiveRecord::Tasks::DatabaseTasks.load_schema_current(:ruby, ENV["SCHEMA"])
    end
  end
end
