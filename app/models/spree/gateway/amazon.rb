##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
module Spree
  class Gateway::Amazon < Gateway
    REGIONS = %w(us uk de jp).freeze

    preference :currency, :string, default: -> { Spree::Config.currency }
    preference :client_id, :string
    preference :merchant_id, :string
    preference :aws_access_key_id, :string
    preference :aws_secret_access_key, :string
    preference :region, :string, default: 'us'

    has_one :provider

    validates :preferred_region, inclusion: { in: REGIONS }

    def self.for_currency(currency)
      where(active: true).detect { |gateway| gateway.preferred_currency == currency }
    end

    def api_url
      sandbox = preferred_test_mode ? '_Sandbox' : ''
      {
        'us' => "https://mws.amazonservices.com/OffAmazonPayments#{sandbox}/2013-01-01",
        'uk' => "https://mws-eu.amazonservices.com/OffAmazonPayments#{sandbox}/2013-01-01",
        'de' => "https://mws-eu.amazonservices.com/OffAmazonPayments#{sandbox}/2013-01-01",
        'jp' => "https://mws.amazonservices.jp/OffAmazonPayments#{sandbox}/2013-01-01",
      }.fetch(preferred_region)
    end

    def widgets_url
      sandbox = preferred_test_mode ? '/sandbox' : ''
      {
        'us' => "https://static-na.payments-amazon.com/OffAmazonPayments/us#{sandbox}/js/Widgets.js",
        'uk' => "https://static-eu.payments-amazon.com/OffAmazonPayments/uk#{sandbox}/lpa/js/Widgets.js",
        'de' => "https://static-eu.payments-amazon.com/OffAmazonPayments/de#{sandbox}/lpa/js/Widgets.js",
        'jp' => "https://origin-na.ssl-images-amazon.com/images/G/09/EP/offAmazonPayments#{sandbox}/prod/lpa/js/Widgets.js",
      }.fetch(preferred_region)
    end

    def supports?(source)
      true
    end

    def method_type
      "amazon"
    end

    def provider_class
      AmazonTransaction
    end

    def payment_source_class
      AmazonTransaction
    end

    def source_required?
      true
    end

    def authorize(amount, amazon_checkout, gateway_options={})
      if amount < 0
        return ActiveMerchant::Billing::Response.new(true, "Success", {})
      end

      order_number, payment_number = extract_order_and_payment_number(gateway_options)
      order = Spree::Order.find_by!(number: order_number)
      payment = Spree::Payment.find_by!(number: payment_number)
      authorization_reference_id = operation_unique_id(payment)

      load_amazon_mws(order.amazon_order_reference_id)

      response = begin
        @mws.authorize(
          authorization_reference_id,
          amount / 100.0,
          order.currency,
          seller_authorization_note: sandbox_authorize_simulation_string(order),
        )
      rescue RuntimeError => e
        raise Spree::Core::GatewayError.new(e.to_s)
      end

      if response.success
        parsed_response = Hash.from_xml(response.body)
        auth_details = parsed_response.fetch('AuthorizeResponse').fetch('AuthorizeResult').fetch('AuthorizationDetails')
        auth_status = auth_details.fetch('AuthorizationStatus')
        auth_state = auth_status.fetch('State')

        if auth_state == 'Open'
          success = true
          order.amazon_transaction.update!(
            authorization_id: auth_details.fetch('AmazonAuthorizationId')
          )
          message = 'Success'
        else
          success = false
          message = "Authorization failure: #{auth_status['ReasonCode']}"
        end
      else
        success = false
        parsed_response = Hash.from_xml(response.body) rescue nil
        if parsed_response && parsed_response['ErrorResponse']
          error = parsed_response.fetch('ErrorResponse').fetch('Error')
          message = "#{response.code} #{error.fetch('Code')}: #{error.fetch('Message')}"
        else
          message = "#{response.code} #{response.body}"
        end
      end

      ActiveMerchant::Billing::Response.new(
        success,
        message,
        {
          'response' => response,
          'parsed_response' => parsed_response,
        },
      )
    end

    def capture(amount, amazon_checkout, gateway_options={})
      if amount < 0
        return credit(amount.abs, nil, nil, gateway_options)
      end
      order_number, payment_number = extract_order_and_payment_number(gateway_options)
      order = Spree::Order.find_by!(number: order_number)
      payment = Spree::Payment.find_by!(number: payment_number)
      authorization_id = order.amazon_transaction.authorization_id
      capture_reference_id = operation_unique_id(payment)

      load_amazon_mws(order.amazon_order_reference_id)

      response = @mws.capture(authorization_id, capture_reference_id, amount / 100.00, order.currency)

      t = order.amazon_transaction
      t.capture_id = response.fetch("CaptureResponse", {}).fetch("CaptureResult", {}).fetch("CaptureDetails", {}).fetch("AmazonCaptureId", nil)
      t.save!
      return ActiveMerchant::Billing::Response.new(response.fetch("CaptureResponse", {}).fetch("CaptureResult", {}).fetch("CaptureDetails", {}).fetch("CaptureStatus", {})["State"] == "Completed", "OK", response)
    end

    def purchase(amount, amazon_checkout, gateway_options={})
      auth_result = authorize(amount, amazon_checkout, gateway_options)
      if auth_result.success?
        capture(amount, amazon_checkout, gateway_options)
      else
        auth_result
      end
    end

    def credit(amount, _response_code, gateway_options = {})
      payment = gateway_options[:originator].payment
      amazon_transaction = payment.source

      load_amazon_mws(amazon_transaction.order_reference)
      response = @mws.refund(
        amazon_transaction.capture_id,
        operation_unique_id(payment),
        amount / 100.00,
        payment.currency
      )
      return ActiveMerchant::Billing::Response.new(true, "Success", response)
    end

    def void(response_code, gateway_options)
      order = Spree::Order.find_by(:number => gateway_options[:order_id].split("-")[0])
      load_amazon_mws(order.amazon_order_reference_id)
      capture_id = order.amazon_transaction.capture_id

      if capture_id.nil?
        response = @mws.cancel
      else
        response = @mws.refund(capture_id, gateway_options[:order_id], order.total, order.currency)
      end

      return ActiveMerchant::Billing::Response.new(true, "Success", response)
    end

    private

    def load_amazon_mws(reference)
      @mws ||= AmazonMws.new(reference, gateway: self)
    end

    def extract_order_and_payment_number(gateway_options)
      gateway_options[:order_id].split("-", 2)
    end

    # Amazon requires unique ids. Calling with the same id multiple times means
    # the result of the previous call will be returned again. This can be good
    # for things like asynchronous retries, but would break things like multiple
    # captures on a single authorization.
    def operation_unique_id(payment)
      "#{payment.number}-#{random_suffix}"
    end

    # A random string of lowercase alphanumeric characters (i.e. "base 36")
    def random_suffix
      length = 10
      SecureRandom.random_number(36 ** length).to_s(36).rjust(length, '0')
    end

    # Allows simulating errors in sandbox mode if the *last* name of the
    # shipping address is "SandboxSimulation" and the *first* name is one of:
    #
    #   InvalidPaymentMethodHard-<minutes> (-<minutes> is optional. between 1-240.)
    #   InvalidPaymentMethodSoft-<minutes> (-<minutes> is optional. between 1-240.)
    #   AmazonRejected
    #   TransactionTimedOut
    #   ExpiredUnused-<minutes> (-<minutes> is optional. between 1-60.)
    #   AmazonClosed
    #
    # E.g. a full name like: "AmazonRejected SandboxSimulation"
    #
    # See https://payments.amazon.com/documentation/lpwa/201956480 for more
    # details on Amazon Payments Sandbox Simulations.
    def sandbox_authorize_simulation_string(order)
      return nil if !preferred_test_mode
      return nil if order.ship_address.nil?
      return nil if order.ship_address.lastname != 'SandboxSimulation'

      reason, minutes = order.ship_address.firstname.to_s.split('-', 2)
      # minutes is optional and is only used for some of the reason codes
      minutes ||= '1'

      case reason
      when 'InvalidPaymentMethodHard' then %({"SandboxSimulation": {"State":"Declined", "ReasonCode":"InvalidPaymentMethod", "PaymentMethodUpdateTimeInMins":#{minutes}}})
      when 'InvalidPaymentMethodSoft' then %({"SandboxSimulation": {"State":"Declined", "ReasonCode":"InvalidPayment Method", "PaymentMethodUpdateTimeInMins":#{minutes}, "SoftDecline":"true"}})
      when 'AmazonRejected'           then  '{"SandboxSimulation": {"State":"Declined", "ReasonCode":"AmazonRejected"}}'
      when 'TransactionTimedOut'      then  '{"SandboxSimulation": {"State":"Declined", "ReasonCode":"TransactionTimedOut"}}'
      when 'ExpiredUnused'            then %({"SandboxSimulation": {"State":"Closed", "ReasonCode":"ExpiredUnused", "ExpirationTimeInMins":#{minutes}}})
      when 'AmazonClosed'             then  '{"SandboxSimulation": {"State":"Closed", "ReasonCode":"AmazonClosed"}}'
      else
        Rails.logger.error('"SandboxSimulation" was given as the shipping first name but the last name was not a valid reason code: ' + order.ship_address.firstname.inspect)
        nil
      end
    end
  end
end
