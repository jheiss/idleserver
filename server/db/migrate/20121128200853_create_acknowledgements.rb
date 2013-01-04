class CreateAcknowledgements < ActiveRecord::Migration
  def change
    create_table :acknowledgements do |t|
      t.integer :client_id, :null => false
      t.datetime :acknowledged_at
      t.datetime :acknowledged_until

      t.timestamps
    end
    add_index :acknowledgements, :client_id
  end
end
