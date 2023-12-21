# Add field to hold whether an outte run has been submitted to a specific userlevel.
# We do this so that we only submit scores to levels that require it in order to
# see the full completion count, without flooding all userlevels with unnecessary
# outte scores.
class AddUserlevelSubmitted < ActiveRecord::Migration[5.1]
  def change
    add_column    :userlevels, :submitted,   :boolean, index: true, default: false
    change_column :userlevels, :completions, :integer, index: true, default: 0
  end
end
