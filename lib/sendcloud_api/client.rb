# frozen_string_literal: true

module SendcloudAPI
  class Client
    DEFAULT_BASE_URL = "https://panel.sendcloud.sc/api/v3/"
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_TIMEOUT = 30

    attr_reader :connection

    def initialize(
      public_key:,
      secret_key:,
      base_url: DEFAULT_BASE_URL,
      open_timeout: DEFAULT_OPEN_TIMEOUT,
      timeout: DEFAULT_TIMEOUT,
      adapter: Faraday.default_adapter
    )
      validate_credential!(:public_key, public_key)
      validate_credential!(:secret_key, secret_key)

      @connection = Connection.new(
        public_key: public_key,
        secret_key: secret_key,
        base_url: base_url,
        open_timeout: open_timeout,
        timeout: timeout,
        adapter: adapter
      )
    end

    def returns
      @returns ||= Resources::Returns.new(connection)
    end

    def shipping_options
      @shipping_options ||= Resources::ShippingOptions.new(connection)
    end

    def parcel_documents
      @parcel_documents ||= Resources::ParcelDocuments.new(connection)
    end

    def parcel_tracking
      @parcel_tracking ||= Resources::ParcelTracking.new(connection)
    end

    def contracts
      @contracts ||= Resources::Contracts.new(connection)
    end

    def integrations
      @integrations ||= Resources::Integrations.new(connection)
    end

    def user
      @user ||= Resources::User.new(connection)
    end

    def invoice_items
      @invoice_items ||= Resources::InvoiceItems.new(connection)
    end

    def inspect
      "#<#{self.class}>"
    end

    private

    def validate_credential!(name, value)
      return if value.is_a?(String) && !value.strip.empty?

      raise ArgumentError, "#{name} must be a non-empty String"
    end
  end
end
