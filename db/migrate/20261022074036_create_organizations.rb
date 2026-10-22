class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :demo, null: false, default: false
      # Pages per day this organization may extract. NULL means no cap.
      t.integer :daily_page_cap

      t.timestamps
    end
    add_index :organizations, :slug, unique: true
    add_check_constraint :organizations, "daily_page_cap IS NULL OR daily_page_cap > 0",
      name: "daily_page_cap_positive"
  end
end
