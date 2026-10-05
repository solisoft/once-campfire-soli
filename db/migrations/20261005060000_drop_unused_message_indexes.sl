# Two message indexes cost a write on every new message and serve nothing:
#
# - (room_id, created_at), persistent: SoliDB's planner never uses a compound index for a
#   filter on its leading field, nor for the sort; pages are served by the room_id hash index.
# - creator_id: only a ban's content removal reads messages by author, which can scan.

def up(db: Any)
  db.drop_index("messages", "idx_messages_room_created")
  db.drop_index("messages", "idx_messages_creator")
end

def down(db: Any)
  db.create_index("messages", "idx_messages_room_created", ["room_id", "created_at"], {"type": "persistent"})
  db.create_index("messages", "idx_messages_creator", ["creator_id"], {})
end
