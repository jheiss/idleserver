class AddNoteUserToAcknowledgements < ActiveRecord::Migration
  def change
    add_column :acknowledgements, :user, :string
    add_column :acknowledgements, :note, :string
  end
end
