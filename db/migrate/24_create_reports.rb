class CreateReports < ActiveRecord::Migration[5.1]
  def change
    GlobalProperty.find_or_create_by(key: 'next_report_update', value: (Time.now + 86400).to_s)
  end
end
