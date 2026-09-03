module LlamaBotRails
  # A product release / version with human-readable update notes. Authored by
  # admins via the releases UI; read by users on the releases page and on the
  # Leonardo feedback bubble's version chip.
  class Release < ApplicationRecord
    validates :version, presence: true, uniqueness: true

    scope :published, -> { where(published: true) }
    scope :ordered, -> { order(Arel.sql("released_at DESC NULLS LAST"), created_at: :desc) }

    # The release matching the version of the running image, if it has been
    # authored. Returns nil for local/source runs (version "dev") or when the
    # admin hasn't created a row for the running version yet.
    def self.current
      find_by(version: LlamaBotRails.app_version)
    end

    # True when this row describes the version of the running image.
    def current?
      version == LlamaBotRails.app_version
    end
  end
end
