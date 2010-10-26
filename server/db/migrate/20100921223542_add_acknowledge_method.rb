class AddAcknowledgeMethod < ActiveRecord::Migration
  def self.up
    change_table :clients do |t|
      t.datetime :acknowledged_at, :default => nil
      t.datetime :acknowledged_until, :default => nil
    end
  end

  def self.down
    remove_column :clients, :acknowledged_at
    remove_column :clients, :acknowledged_until
  end
end
