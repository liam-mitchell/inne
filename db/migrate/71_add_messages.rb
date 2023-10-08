# Create a db table to log each message outte sends and who it is in response to
# That way, that user may later request to delete that message
class AddMessages < ActiveRecord::Migration[5.1]
  def change
    create_table :messages do |t|
      t.integer :user_id, limit: 8, index: true
      t.timestamp :date
    end
  end
end