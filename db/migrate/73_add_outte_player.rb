class AddOuttePlayer < ActiveRecord::Migration[5.1]
  def change
    Player.find_or_create_by(metanet_id: 361131).update(
      name:     'outte++',
      steam_id: '76561199562076498'
    )
  end
end