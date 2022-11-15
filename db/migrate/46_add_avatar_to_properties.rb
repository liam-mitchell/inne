class AddAvatarToProperties < ActiveRecord::Migration[5.1]
  def change
    # Can't retrieve current avatar, will be updated whenever it's changed
    # That way we don't repeat it when faceswapping
    GlobalProperty.find_or_create_by(key: 'avatar').update(value: 'none')
  end
end