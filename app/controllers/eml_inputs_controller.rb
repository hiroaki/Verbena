# frozen_string_literal: true

# デモ用: Web フォームから EML を Verbena API に投入する
class EmlInputsController < ApplicationController
  # 妥当性検証エラーなど、ユーザー起因のエラーを表す例外
  class InputError < StandardError; end

  # アップロード時の EML 最大許容サイズ（デモ用: 10MB）
  # - 実運用では環境設定化することを推奨
  MAX_EML_UPLOAD_SIZE = 10.megabytes

  def new
    @fields_values = {}
    @upload_values = {}
    @token = nil
    @sent_at = nil
  end

  def create
    sent_at = params[:sent_at]
    token = params[:token].to_s.strip
    validate_token!(token)

    # EMLファイルがアップロードされていればuploadモード、なければfieldsモード
    is_upload = params[:upload].present? && params[:upload][:eml_file].present?
    mail = is_upload ? process_upload_mode! : process_fields_mode!

    # 送信
    response = deliver_mail(mail, token, sent_at)
    Rails.logger.info("deliver_main and returns:  #{response.inspect}")

    # Try to extract created MailQueue IDs from the API response body (JSON)
    results = parse_results!(response.body)
    notice = "送信しました (作成ID: #{results.join(',')})"

    flash[:notice] = notice
    redirect_to new_eml_input_path
  rescue InputError, Verbena::HttpDelivery::DeliveryError => ex
    Rails.logger.warn("eml.inputs#create user error: #{ex.class}: #{ex.message}")
    flash.now[:alert] = "送信に失敗しました: #{ex.message}"
    render_error_restoring_inputs
  rescue => ex
    Rails.logger.error("eml.inputs#create unexpected error: #{ex.class}: #{ex.message}\n#{ex.backtrace.join("\n")}")
    flash.now[:alert] = "システムエラーが発生しました"
    render_error_restoring_inputs
  end

  private

  # アップロードモード: EMLファイル → Mail オブジェクト
  def process_upload_mode!
    validate_eml_file!(upload_params[:eml_file])
    Mail.new(upload_params[:eml_file].read)
  end

  # フィールドモード: フォーム入力 → Mail オブジェクト
  def process_fields_mode!
    build_mail_from_fields(fields_params)
  end

  # Mail オブジェクトの構築（フィールドモード専用）
  def build_mail_from_fields(attrs)
    mail = Mail.new
    mail.to = split_addresses(attrs[:to])
    mail.cc = split_addresses(attrs[:cc])
    mail.bcc = split_addresses(attrs[:bcc])
    mail.from = attrs[:from] if attrs[:from].present?
    mail.subject = attrs[:subject] if attrs[:subject].present?
    mail.body = attrs[:body] if attrs[:body].present?
    mail.date = Time.current
    mail
  end

  # Mail オブジェクトの配送（共通処理）
  # 戻り値: Verbena::HttpDelivery が返す HTTP 風のレスポンスオブジェクト（#code を期待）
  # 期待形でない場合はログに警告を出します。
  def deliver_mail(mail, token, sent_at = nil)
    # BCCヘッダを配送時に含めるために明示的に有効化
    mail[:bcc].include_in_headers = true if mail[:bcc]

    if sent_at.present?
      mail.date = parsed_time_or_nil(sent_at) || Time.current
    end

    mail.delivery_method(Verbena::HttpDelivery, delivery_settings(token))
    result = mail.deliver!

    unless result.respond_to?(:code)
      Rails.logger.warn("deliver_mail: adapter returned unexpected result: #{result.inspect}")
    end

    result
  end

  # バリデーション: Token
  def validate_token!(token)
    raise InputError, 'Tokenを入力してください' if token.blank?
  end

  # バリデーション: EMLファイル
  def validate_eml_file!(upload)
    raise InputError, 'EMLファイルを選択してください' unless upload.present?

    # 拡張子チェック（ブラウザ側の accept 属性はあてにならないためサーバ側でも確認）
    if upload.respond_to?(:original_filename)
      fname = upload.original_filename.to_s
      if File.extname(fname).downcase != '.eml'
        raise InputError, 'EMLファイル（.eml）を選択してください'
      end
    end

    # サイズチェックの意図:
    # - 可能ならば upload.size を優先して判定し、read を行わずに早期判定する。
    # - 一部の Rack/ストリーミング実装では size が使えないことがあるため、その場合は
    #   安全のため最大サイズ+1 バイトだけ読み取り (空ファイル検出と上限検出のため) を行う。
    max_size = MAX_EML_UPLOAD_SIZE

    if upload.respond_to?(:size) && !upload.size.nil?
      raise InputError, 'EMLが空です' if upload.size.to_i == 0
      raise InputError, "EMLファイルが大きすぎます (最大 #{max_size} バイト)" if upload.size.to_i > max_size
    else
      if upload.respond_to?(:read)
        content = upload.read(max_size + 1)
        raise InputError, 'EMLが空です' if content.blank?
        raise InputError, 'EMLファイルが大きすぎます' if content.bytesize > max_size
        upload.rewind if upload.respond_to?(:rewind)
      else
        content = upload.to_s
        raise InputError, 'EMLが空です' if content.blank?
      end
    end
  end

  def render_error_restoring_inputs
    # エラー時は入力値を保持して再表示
    # params[:fields] がない場合も想定して安全に取得
    raw_fields = params[:fields]
    @fields_values = if raw_fields.respond_to?(:permit)
                       raw_fields.permit(:to, :cc, :bcc, :from, :subject, :body).to_h.symbolize_keys
                     else
                       {}
                     end

    @upload_values = {}

    # Ensure token/sent_at are available to the view when rendering
    @token = params[:token]
    @sent_at = params[:sent_at]

    # Render new with preserved inputs for HTML clients
    flash.now[:alert] ||= "送信に失敗しました"
    render :new, status: :unprocessable_entity
  end

  def delivery_settings(token)
    {
      url_enqueue: endpoint_url,
      access_token: token,
      logger: Rails.logger,
      verify_ssl: false, # 開発環境(デモ)用なのでSSL検証をスキップ
      return_response: true, # 成功時にステータスコードを表示したいためレスポンスを要求
    }
  end

  def endpoint_url
    env_url = ENV['VERBENA_API_ENDPOINT_URL'].to_s.strip
    return env_url unless env_url.blank?

    # 【実装時の注意点: デモ用コードとしての背景】
    # このコードは「Verbenaを利用する外部システム」の実装サンプルですが、
    # デモ環境の都合上、APIサーバー(Verbena)と同じコンテナ内で動作しています。
    #
    # 通常、外部システムからは正式なAPIのURL(https://api.example.com など)を設定しますが、
    # ここでは設定がない場合のフォールバックとして「自分自身(localhost)」を指しています。
    #
    # 1. request.base_url を使わない理由:
    #    これは「ブラウザから見たURL(例: Port 23000 / https)」を返しますが、
    #    コンテナ内部のプロセス間通信は `http://127.0.0.1:3000` で行われるため、
    #    外向けの情報をそのまま使うと接続できません。
    #
    # 2. http スキーム固定の理由:
    #    外部アクセスが HTTPS でも、コンテナ内部は HTTP で待受けるのが一般的(SSLオフロード)です。
    #
    # Rails自体にはリッスンポートを知る標準APIがないため、
    # 慣習的に PORT 環境変数かデフォルトの 3000 を使用します
    port = ENV['PORT'].presence || 3000
    "http://127.0.0.1:#{port}/api/v1/mail_queues"
  end

  def parsed_time_or_nil(raw)
    return nil if raw.blank?

    Time.zone.parse(raw)
  rescue
    nil
  end

  def split_addresses(raw)
    return [] if raw.blank?
    Mail::AddressList.new(raw.to_s).addresses.map(&:address).reject(&:blank?)
  rescue Mail::Field::ParseError
    raise InputError, '不正なメールアドレス形式が含まれています'
  end

  def fields_params
    raw = params[:fields]
    if raw.respond_to?(:permit)
      raw.permit(:to, :cc, :bcc, :from, :subject, :body)
    else
      ActionController::Parameters.new
    end
  end

  def upload_params
    raw = params[:upload]
    if raw.respond_to?(:permit)
      raw.permit(:eml_file)
    else
      ActionController::Parameters.new
    end
  end

  def parse_results!(body)
    parsed = JSON.parse(body)
    return parsed['ids']
  rescue JSON::ParserError => ex
    Rails.logger.error("parse_results JSON parse error: #{ex.class}: #{ex.message}")
    raise ex
  end
end
