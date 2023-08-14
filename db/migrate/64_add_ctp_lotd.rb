class AddCtpLotd < ActiveRecord::Migration[5.1]
  def change
    add_column :mappack_levels,   :completed, :boolean
    add_column :mappack_episodes, :completed, :boolean
    add_column :mappack_stories,  :completed, :boolean
    ['level', 'episode', 'story'].each{ |type|
      time = GlobalProperty.find_by(key: "next_#{type}_update").value
      GlobalProperty.find_or_create_by(key: "next_ctp_#{type}_update")
                    .update(value: time)
      GlobalProperty.find_or_create_by(key: "current_ctp_#{type}")
                    .update(value: nil)
      GlobalProperty.find_or_create_by(key: "saved_ctp_#{type}_scores")
                    .update(value: [])
    }
  end
end