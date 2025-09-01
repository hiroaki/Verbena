class Token < ApplicationRecord
  DIGEST_ALGORITHM = Digest::SHA512

  attr_accessor :key

  validates :label, presence: true
  validates :key, presence: true

  before_save :digest_hash

  def self.authenticated?(str)
    return false if str.blank?

    digest = DIGEST_ALGORITHM.hexdigest(str)
    # Note: use a single query to fetch a valid token, then update last_used_at if found
    tok = where(key_digest_hash: digest)
            .where(revoked_at: nil)
            .where("expires_at > ?", Time.current)
            .first
    if tok
      # Update last_used_at (best-effort; ignore race errors)
      begin
        tok.update_columns(last_used_at: Time.current)
      rescue => e
        Rails.logger.warn("[Token] last_used_at update failed id=#{tok.id} error_class=#{e.class} error=#{e.message}")
      end
      true
    else
      false
    end
  end

  # TODO: scope support (e.g., read-only tokens). Add column and checks in the future.

  private

  def digest_hash
    self.key_digest_hash = DIGEST_ALGORITHM.hexdigest(key)
  end
end
