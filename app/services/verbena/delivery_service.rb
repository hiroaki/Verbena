# 使い方：
#
#   # 未処理の MailQueue について送信する
#   Verbena::DeliveryService.new.perform_by_timer
#
#   # 未処理の MailQueue について指定した id のものだけ送信する
#   Verbena::DeliveryService.new.perform_by_mail_queue_id(id)
#
#   # ステータス 4xx のものを再送する（再送の準備をする）
#   #   ... 現在の構想では、最新の送信結果のステータスが 4xx となっている MailQueue を「未処理」に戻すことにしています。
#   #   （したがって、次回の #perform_by_timer 実行時に再度、送信処理の対象となります。）
#   #   ただし考慮すべき事柄は多くあります（一部の事柄はこのアプリの範疇外かもしれません）：
#   #   - 再送信のインターバル
#   #   - 最大回数、または最大経過時間（最初の送信から、現在時刻までの時間。たとえば「72時間までは再送信を試みる」）
#   #   - 最大数を超えた場合、そのレコードを再送信対象からの除外、および管理者への通知方法
#   #   - などなど...
#   Verbena::DeliveryService.new(session_id: value).prepare_to_retry_for_session(timelimit)
#
#   # 配送結果が存在しないものを再送する（再送の準備をする）
#   #   ... こちらも「未処理」に戻す処理をします。
#   #   対象となるレコードは処理結果（関連する DeliveryResponse ）が存在しないものですが、
#   #   配送プロセスが処理中の場合が（可能性としては）あるため、
#   #   その session_id のプロセスが終了しているかを事前に動作ログで確認するようにしてください。
#   Verbena::DeliveryService.new(session_id: value).prepare_to_retry_undelivered
#
module Verbena
  class DeliveryService < ServiceBase
    include DeliveryHelper

    # 変更不可
    attr_reader :session_id

    # timelimitの上限（1年、秒数）
    MAX_TIME_LIMIT_SECONDS = 1.year.freeze

    # timelimitのデフォルト値（72時間、秒数）
    DEFAULT_TIME_LIMIT_SECONDS = 72.hours.freeze

    # インスタンスの識別子を発行します。
    # MailQueue のレコードはこの値によって処理対象であることの印が付けられます。
    def self.issue_session_id
      MailQueue.issue_session_id
    end

    def initialize(options = {})
      super

      # session_id を指定するとき、過去に処理した（処理が完了した）ものである必要があります。
      # - #issue_session_id によって将来生成される可能性がある値を指定しないこと
      # - 過去に処理していないものを対象としたい場合は自動生成 #issue_session_id でよい
      # - リセットの操作は過去に処理したものを指定するため
      # TODO: そのためのチェックとして、 session_id で find するようにします。
      # TODO: @session_id についてその値（文字列）パターンのチェック
      @session_id = options[:session_id].presence || self.class.issue_session_id
    end

    # 一度も処理されていないレコードの中で、
    # 現在時刻がタイマー時刻を経過しているレコードを対象にした送信処理を実行します。
    def perform_by_timer
      MailQueue.claim_by_timer!(session_id)
      perform
    end

    # 一度も処理されていないレコードの中で、
    # mail_queue_id で指定した mail_queues.id のレコードを対象にした送信処理を実行します。
    def perform_by_mail_queue_id(mail_queue_id)
      MailQueue.claim_by_id!(session_id, mail_queue_id)
      perform
    end

    # 指定した session_id による配送処理の結果がステータス 4xx である対象の MailQueue のレコードを、
    # 再処理可能な状態にリセットします。
    # ただしその session_id による最古の配送時刻から timelimit 時間が経過している場合は処理しません。
    def prepare_to_retry_for_session(timelimit = nil)
      reset_mail_queues(
        DeliveryResponse.last_status_4xx_within_time_limit(parse_timelimit_seconds(timelimit)).map(&:mail_queue_id)
      )
    end

    # 指定した session_id による配送処理の結果が存在しない MailQueue のレコードを、
    # 再処理可能な状態にリセットします。
    # このメソッドは単に、関連する DeliveryResponse にレコードが存在しない MailQueue(s) を対象にします。
    # 注意点として、指定した session_id による配送処理が、完了しているか否かはこのメソッドの範疇外です。
    # このメソッドを実行する際には、配送時の動作ログをチェックし、
    # 指定した session_id による配送処理が完了していることを確認のうえ、実行するようにしてください。
    def prepare_to_retry_undelivered
      reset_mail_queues(
        MailQueue.undelivered.where(session_id: session_id).map(&:id)
      )
    end

    # このインスタンスで処理したレコードのうち、レコードの id が mail_queue_ids のものについて、
    # レコードの session_id をクリアします（ =「一度も処理していない」状態に戻します）。
    # この処理によって、該当するレコードを、新たなセッションで処理できるようになります。
    # NOTE:
    #   #claimed のレコードに限定しているのは、その印がないレコードはほかのセッションが処理している可能性があるためです。
    def reset_mail_queues(mail_queue_ids)
      MailQueue.claimed(session_id).where(id: Array(mail_queue_ids)).update_all(session_id: nil, claimed_at: nil, updated_at: Time.current)
    end

    # "claim されている" レコードを対象にした送信処理を実行します。
    # 通常は claim されているレコードがない状況から始めることになるため、
    # このメソッドではなくいずれかの perform_by_... メソッドを利用します。
    def perform
      MailQueue.claimed(session_id).in_batches(**config_for_in_batches) do |rel|
        Parallel.each(rel.all, config_for_parallel) do |mail_queue|
          perform_one(mail_queue)
        end
      end
    end

    # mail_queue のメールを送信し、結果をテーブル delivery_responses に記録します。
    # 送信時に例外が発生した際は、レスポンスコード 451 としています。
    # これは必ずしも SMTP サーバからの返答ではないことに注意してください。
    def perform_one(mail_queue)
      res = mail_queue.delivery_responses.new(responded_at: Time.current)

      loglevel = :info
      message = nil

      begin
        send_mail!(mail_queue) do |mail, response|
          res.message_id = mail.message_id
          res.status = response.status
          # string が列の幅を超えると ActiveRecord::ValueTooLong ですので、明示的に切り詰めてこれを避けます。
          # 通常はもっと短い文章です。
          res.contents = response.string.chomp.truncate(250)

          if response.status == '250'
            message = structured_log(
              event: 'deliver.result', level: 'info', session_id: session_id,
              mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status,
              message: "OK sending a message mail_queues.id=[#{mail_queue.id}] Message-ID=<#{mail.message_id}>, response: status=[#{res.status}] string=[#{res.contents}]"
            )
            loglevel = :info
          else
            message = structured_log(
              event: 'deliver.result', level: 'error', session_id: session_id,
              mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status,
              message: "NG sending a message mail_queues.id=[#{mail_queue.id}] Message-ID=<#{mail.message_id}>, response: status=[#{res.status}] string=[#{res.contents}]"
            )
            loglevel = :error
          end
        end
      rescue => ex
        loglevel = :error
        message = structured_log(
          event: 'deliver.exception', level: 'error', session_id: session_id,
          mail_queue_id: mail_queue.id, smtp_status: 451,
          error: "#{ex.class}: #{ex.message}", message: "NG sending a message mail_queues.id=[#{mail_queue.id}]: #{ex.inspect}"
        )

        # NOTE: #send_mail! にて例外が発生する場合があり、それは SMTP レスポンスとは厳密には違いますが、
        # 送信できなかったというレスポンスを受けた、という体で、 delivery_responses へ登録します。
        # たとえば実際の例として、 RCPT TO コマンドに渡すメールアドレスが不正な書式であったときは Net::SMTPSyntaxError が発生します。
        #
        # TODO: status コードは再利用するわけではないので、 999 などといった独自のエラーコードを設定してもよいかもしれません。
        # 現在のコードでセットしている 451 は暫定的なものです。
        res.status = 451 # "Requested action aborted: local error in processing"
        res.contents = ex.inspect
      ensure
        logger.send(loglevel, message)

        if res.save
          logger.info(structured_log(event: 'delivery_response.created', level: 'info', session_id: session_id, mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status, message: "CREATED DeliveryResponse #{res.id}"))
        else
          logger.error(structured_log(event: 'delivery_response.create_failed', level: 'error', session_id: session_id, mail_queue_id: mail_queue.id, message_id: res.message_id, smtp_status: res.status, error: res.errors.inspect, message: 'FAILED to create DeliveryResponse'))
        end
      end
    end

    # mail_queue のメールを送信します。
    def send_mail!(mail_queue, &block)
      mail = create_mail_message(mail_queue.eml)
      mail.smtp_envelope_from(mail_queue.envelope_from)
      mail.smtp_envelope_to(mail_queue.envelope_to)

      response = mail.deliver!
      # Mail::TestMailer や :file の場合、Net::SMTP::Response を返さないため合成します。
      unless response.is_a?(Net::SMTP::Response)
        response = Net::SMTP::Response.parse('250 OK (synthetic by Verbena)')
      end

      if block_given?
        yield mail, response
      else
        [mail, response]
      end
    end

    private

    # 指定されたtimelimit（"HH:MM:SS"形式の文字列）を秒数（Integer）に変換し、妥当性を検証します。
    # "HH:MM:SS" 形式以外は受け付けません。柔軟なパースはせず、明示的な失敗でバグ混入を防ぎます。
    # 例: "12:34:56" のみ許容。分・秒は常に2桁、時間は0以上の整数。
    def parse_timelimit_seconds(timelimit)
      return DEFAULT_TIME_LIMIT_SECONDS if timelimit.nil?

      unless timelimit.is_a?(String) && !timelimit.empty?
        raise ArgumentError, 'timelimit must be a non-empty string in format HH:MM:SS (hours can be any non-negative integer, minutes and seconds must be between 00 and 59)'
      end

      m = /\A(\d+):([0-5]\d):([0-5]\d)\z/.match(timelimit)
      raise ArgumentError, 'timelimit must be a string in format HH:MM:SS (hours can be any non-negative integer, minutes and seconds must be between 00 and 59)' unless m

      # 文字列から整数へ変換
      hours, minutes, seconds = m.captures.map(&:to_i)
      total_seconds = hours * 3600 + minutes * 60 + seconds

      raise ArgumentError, 'timelimit must be positive' if total_seconds <= 0

      if total_seconds > MAX_TIME_LIMIT_SECONDS
        raise ArgumentError, "timelimit is too large (must be less than or equal to #{MAX_TIME_LIMIT_SECONDS} seconds, about 1 year)"
      end

      total_seconds
    end
  end
end
