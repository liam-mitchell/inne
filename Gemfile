source 'https://rubygems.org' do
  gem 'ascii_charts'
  gem 'discordrb', github: 'shardlab/discordrb', branch: 'main'
  gem 'activerecord'
  gem 'yaml_db'
  gem 'rails', '~> 5.1.5'
  gem 'mysql2'
  gem 'damerau-levenshtein'
  gem 'rubyzip'
  gem 'unicode-emoji'

  group :imaging do
    gem 'rmagick'
    gem 'gruff'
    gem 'chunky_png'
    gem 'oily_png', github: 'edelkas/oily_png', branch: 'dev'
    gem 'matplotlib'
    gem 'svg-graph'
  end

  group :debug, :test do
    gem 'byebug'
    gem 'memory_profiler'
  end

  group :test do
    gem 'test-unit'
    gem 'mocha'
    gem 'database_cleaner'
    gem 'factory_bot'
  end
end
