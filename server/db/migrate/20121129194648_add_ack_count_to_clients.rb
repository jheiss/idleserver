class AddAckCountToClients < ActiveRecord::Migration
  def change
    add_column :clients, :ack_count, :integer
  end
end
