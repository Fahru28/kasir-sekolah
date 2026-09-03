module LlamaBotRails
  class Tagging < ApplicationRecord
    belongs_to :tag
    belongs_to :taggable, polymorphic: true

    validates :tag_id, uniqueness: { scope: [:taggable_type, :taggable_id] }

    def tagged_by_user
      LlamaBotRails.user_resolver&.call(tagged_by_user_id) if tagged_by_user_id
    end
  end
end
