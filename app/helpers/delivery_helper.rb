module DeliveryHelper
  # EML形式のテキストデータ eml をもとに、送信可能な Mail::Massage のインスタンスを生成します。
  # そのインスタンスの #deliver! を呼ぶことで、そのメールを送信します。
  # なおこのインスタンスの #deliver! の返却値は、 SMTP のレスポンスを Net::SMTP::Response のインスタンスで返します。
  def create_mail_message(eml, method: nil)
    # delivery_method は Settings で決定されます（未指定時は環境に応じた既定値）。
    method ||= selected_delivery_method
    configure_mail_delivery_method(Mail.read_from_string(eml), method)
  end

  # Mail::Message のインスタンス mail_message に、Rails 設定から delivery_method に関係する配送設定をセットします。
  # 設定された mail_message を返します。
  # 現在サポートしている delivery_method は :smtp / :test / :file です。
  def configure_mail_delivery_method(mail_message, delivery_method)
    mail_message.tap do |this|
      method_sym = delivery_method.to_sym
      case method_sym
      when :smtp
        this.delivery_method(:smtp, config_for_delivery_method(:smtp))
      when :test
        this.delivery_method(Mail::TestMailer)
      when :file
        this.delivery_method(Mail::FileDelivery, config_for_delivery_method(:file))
      else
        this.delivery_method(:smtp, config_for_delivery_method(:smtp))
      end
    end
  end

  # delivery_method ごとの設定を環境変数から構築します。
  # :smtp の場合は `return_response: true` を付与します。
  def config_for_delivery_method(delivery_method)
    case delivery_method
    when :smtp
      Verbena::Settings.smtp_delivery_config
    when :test
      {}
    when :file
      Verbena::Settings.file_delivery_config
    else
      {}
    end
  end

  # 並列処理のためのオプションパラメタを返します。
  def config_for_parallel
    Verbena::Settings.parallel_config
  end

  # 処理対象のレコードを分割して処理するための in_batches に渡すオプションパラメタを返します。
  def config_for_in_batchs
    Verbena::Settings.in_batches_config
  end

  private

  # 配送方式を Settings から取得します。
  # - 戻り値は :smtp / :test / :file のいずれか（Symbol）
  # - 既定値は Settings 側で環境に応じて決まります
  def selected_delivery_method
    Verbena::Settings.delivery_method
  end

  # file 配送（Mail::FileDelivery）時の保存先ディレクトリ。
  # - VERBENA_FILE_DELIVERY_DIR が未設定の場合は Rails.root/tmp/mails を使用
  # - 実ディレクトリの作成は初期化子（config/initializers/verbena_env.rb）で行います
  def file_delivery_dir
    Verbena::Settings.file_delivery_dir
  end
end
