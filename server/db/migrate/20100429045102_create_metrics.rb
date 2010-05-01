class CreateMetrics < ActiveRecord::Migration
  def self.up
    create_table :metrics do |t|
      t.integer :client_id, :null => false
      t.string  :name, :null => false
      t.integer :idleness, :null => false
      t.text    :message, :null => false
      t.timestamps
    end
    add_index :metrics, :client_id
    add_index :metrics, :name
  end

  def self.down
    drop_table :metrics
  end
end
