module LlamaBotRails
  class SharedLink < ApplicationRecord
    belongs_to :attachment, class_name: 'ActiveStorage::Attachment'

    validates :token, presence: true, uniqueness: true
    validates :attachment, presence: true

    before_validation :generate_token, on: :create

    scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
    scope :expired, -> { where('expires_at <= ?', Time.current) }

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def active?
      !expired?
    end

    def increment_view_count!
      increment!(:view_count)
    end

    # Get the blob through the attachment
    def blob
      attachment&.blob
    end

    # Convenience methods for attachment info
    delegate :filename, :content_type, :byte_size, to: :blob, allow_nil: true

    def video?
      content_type&.start_with?('video/')
    end

    def image?
      content_type&.start_with?('image/')
    end

    private

    def generate_token
      self.token ||= SecureRandom.urlsafe_base64(16)
    end
  end
end
