class AddTwitchToken < ActiveRecord::Migration[5.1]
  def change
    GlobalProperty.find_or_create_by(key: 'twitch_token').update(value: nil)
  end
end
