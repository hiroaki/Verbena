module Verbena
  class CleanupService < ServiceBase
    # Options
    # - expiration: Time (required unless using builder)
    # - dry_run: boolean (when true, do not delete; just return counts)

    # shorthand
    def self.now(options = {})
      new(options.merge(expiration: Time.current))
    end

    # shorthand
    def self.daily(options = {})
      new(options.merge(expiration: Time.current - 1.day))
    end

    # shorthand
    def self.weekly(options = {})
      new(options.merge(expiration: Time.current - 1.week))
    end

    # shorthand
    def self.monthly(options = {})
      new(options.merge(expiration: Time.current - 1.month))
    end

    # Build from VERBENA_CLEANUP_TTL_DAYS (via Verbena::Settings).
    # Default is 30 days when ENV is not provided. See initializer for validation.
    def self.by_ttl(options = {})
      days = Verbena::Settings.cleanup_ttl_days
      new(options.merge(expiration: Time.current - days.days))
    end

    def initialize(options = {})
      super

      # 保存期限 ... 削除の条件のひとつで、配信処理日時がこの日時よりも未来のレコードは削除の対象にはなりません。
      self.expiration = options[:expiration].presence || Time.current

      # dry-run mode
      @dry_run = !!options[:dry_run]
    end

    def expiration
      @expiration
    end

    def expiration=(something)
      @expiration = _parse_datetime(something).presence || raise(ArgumentError.new('could not be parsed as time'))
    end

    def _parse_datetime(something)
      Time.zone.parse(something.to_s)
    end

    # 不要となった mail_queues および eml_sources のレコードを削除します。
    # （なおひとつの mail_queue の削除は、連動して関連する delivery_responses も削除します）
    #
    # mail_queues について、不要となるのは次の条件をすべて満たす時です：
    # - 送信済みである = session_id が nil ではない
    # - 送信済みである = delivery_responses に記録がある（複数あることもあります）
    # - そのひとつの delivery_responses.responded_at が、expiration よりも前の日時である
    #
    # また eml_sources について、不要となるのは次の条件を満たす時です：
    # - 自身を参照する mail_queues が存在しない
    # Returns a summary hash of affected record counts.
    # Example: { mail_queues: 10, eml_sources: 3 }
    def cleanup
      mq = cleanup_mail_queues
      es = cleanup_eml_sources
      { mail_queues: mq, eml_sources: es }
    end

    # 送信処理が行われており、かつ保存期限を過ぎた mail_queues （および関連する delivery_responses ）を削除します。
    #
    # NOTE: DeliveryResponse が存在すれば一度は処理済みなのですが、
    #   その後何らかの理由で session_id を未処理状態 nil に更新された場合は、
    #   未処理（再処理待ち）として扱うことが考えられるため、
    #   session_id IS NULL のレコードは削除対象から除外するように条件を追加しています。
    #
    # NOTE: 運用の観点からの注意点です。一度でも配送処理が行われていれば、その配送の結果にかかわらず、削除対象となります。
    #   たとえばある MailQueue について、エラーレスポンスが記録されている場合、そのメールは配送先には届いていません。
    #   再送の手続きや、配送失敗の原因追跡調査などにレコードを再利用するには、削除のスケジュールに余裕を持たせるようにしてください。
    def cleanup_mail_queues
      scope = MailQueue
        .joins(:delivery_responses)
        .where(delivery_responses: { responded_at: ...expiration }) # "...expiration" は "< expiration" です
        .where.not(session_id: nil)
      if @dry_run
        # count distinct mail_queue ids to avoid double counting due to joins
        scope.distinct.count
      else
        scope.destroy_all.size
      end
    end

    # 自身を参照している mail_queues がひとつもない eml_sources を削除します。
    def cleanup_eml_sources
      # NOTE: パフォーマンス優先のために #delete_all を使っています。
      # もし仮にここを #destroy_all にした場合、コールバックが走りますが、
      # その内容は mail_queue を destroy するだけですので、ここではまったくの無駄な処理になってしまいます。
      scope = EmlSource.left_outer_joins(:mail_queues).where(mail_queues: { id: nil })
      if @dry_run
        scope.count
      else
        scope.delete_all
      end
    end

  end
end
