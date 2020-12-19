class FixSecretNames < ActiveRecord::Migration[5.1]
  def change
    20.times.each{ |i|
      Level.find(1900 + i).update(name: "?-X-#{"%02d" % i}")
      Level.find(3100 + i).update(name: "!-X-#{"%02d" % i}")
    }
  end
end
