class Token < ApplicationRecord
  # Token は、管理者のみが発行・更新を行うことを前提に設計されています。
  # エンドユーザーは Token を使用するのみで、作成や更新権限は持ちません。
  #
  # 運用方針（重要）:
  # - 発行後の `key` は更新禁止とします（モデルの `prevent_key_change` によって
  #   enforce されます）。キーを変更する場合は既存トークンを `revoke!` で無効化し、
  #   新しいトークンを作成してください。物理削除ではなく `revoked_at` を使った
  #   無効化を推奨します（監査保持のため）。
  #
  # セキュリティ考慮：
  # - key_digest_hash は UNIQUE 制約を持ちます。これにより、同じ key を持つ
  #   複数の token が存在することを防ぎ、token の一意性を保証します。
  # - 管理者のみが操作するため、バリデーションエラーメッセージから key の
  #   情報が漏洩する危険性はありません。
  #
  # TODO: scope support (e.g., read-only tokens). Add column and checks in the future.

  DIGEST_ALGORITHM = Digest::SHA512

  attr_accessor :key
  validates :label, presence: true
  validates :expires_at, presence: true
  validates :key, presence: true, on: :create
  validate :prevent_key_change, on: :update

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
  scope :expired, -> { where(revoked_at: nil).where("expires_at <= ?", Time.current) }

  # Note: expiration detection is exposed via `scope :expired`.
  # Revocation (setting `revoked_at`) is intentionally left to callers
  # so that the act of revoking is an explicit operation with its own
  # responsibilities (audit logging, callbacks, etc.).

  before_create :digest_hash

  # Helper to translate DB unique constraint violations into validation errors
  # when creating tokens.
  # Note: we intentionally do NOT use `validates :key, uniqueness: true` because
  # it has an inherent race window; the DB unique index is the source of truth.
  # Use this helper to ensure that duplicate keys and/or labels raise RecordInvalid
  # with an error on the corresponding attribute (`key` and/or `label`),
  # instead of bubbling up RecordNotUnique from the DB adapter.
  def self.create_unique!(attrs)
    create!(attrs)
  rescue ActiveRecord::RecordNotUnique
    token = new(attrs)
    found = false

    if attrs[:label].present? && Token.exists?(label: attrs[:label])
      token.errors.add(:label, :taken)
      found = true
    end

    if attrs[:key].present?
      digest = DIGEST_ALGORITHM.hexdigest(attrs[:key])
      if Token.exists?(key_digest_hash: digest)
        token.errors.add(:key, :taken)
        found = true
      end
    end

    unless found
      # A generic base error is added as a fallback if the violated
      # constraint cannot be determined.
      # Note: There is a rare race condition where the conflicting record
      # could be deleted between the RecordNotUnique exception and the
      # exists? checks above. In that case, we fall back to this generic error.
      token.errors.add(:base, :taken)
    end

    raise ActiveRecord::RecordInvalid, token
  end

  def self.authenticated?(str)
    return false if str.blank?

    digest = DIGEST_ALGORITHM.hexdigest(str)
    # Note: use a single query to fetch a valid token, then update last_used_at if found
    tok = where(key_digest_hash: digest)
            .where(revoked_at: nil)
            .where("expires_at > ?", Time.current)
            .first

    return false unless tok

    # Update last_used_at (best-effort; ignore race errors)
    begin
      tok.update_columns(last_used_at: Time.current)
    rescue StandardError => e
      Rails.logger.warn("[Token] last_used_at update failed id=#{tok.id} error_class=#{e.class} error=#{e.message}")
    end
    true
  end

  # Explicit revocation helper (sets revoked_at).
  def revoke!(time = Time.current)
    update!(revoked_at: time)
  end

  def active?
    # expires_at.present? is a defensive guard for unsaved tokens
    revoked_at.nil? && expires_at.present? && expires_at > Time.current
  end

  private

  def prevent_key_change
    if key_digest_hash_changed?
      errors.add(:key, :invalid, message: 'cannot be changed; revoke and recreate instead')
    end
  end

  def digest_hash
    return if key.blank?
    self.key_digest_hash = DIGEST_ALGORITHM.hexdigest(key)
    # Clear the plain `key` from memory after digesting to avoid accidental reuse
    self.key = nil
  end
end
