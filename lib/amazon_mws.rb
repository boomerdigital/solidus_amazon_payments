##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##

require 'pay_with_amazon'

class AmazonMwsOrderResponse
  def initialize(response)
    @response = response.fetch("GetOrderReferenceDetailsResponse", {})
  end

  def destination
    @response.fetch("GetOrderReferenceDetailsResult", {}).fetch("OrderReferenceDetails", {}).fetch("Destination", {})
  end

  def constraints
    @response.fetch("GetOrderReferenceDetailsResult", {}).fetch("OrderReferenceDetails", {}).fetch("Constraints", {}).fetch("Constraint", {})
  end

  def state
    @response.fetch("GetOrderReferenceDetailsResult", {}).fetch("OrderReferenceDetails", {}).fetch("OrderReferenceStatus", {}).fetch("State", {})
  end

  def total
    total_block = @response.fetch("GetOrderReferenceDetailsResult", {}).fetch("OrderReferenceDetails", {}).fetch("OrderTotal", {})
    Spree::Money.new(total_block.fetch("Amount", 0), :with_currency => total_block.fetch("CurrencyCode", "USD"))
  end

  def email
    @response.fetch("GetOrderReferenceDetailsResult", {}).fetch("OrderReferenceDetails", {}).fetch("Buyer", {}).fetch("Email", {})
  end
end

class AmazonMws
  require 'httparty'

  def initialize(amazon_order_reference_id, gateway:)
    @amazon_order_reference_id = amazon_order_reference_id
    @gateway = gateway
  end


  def fetch_order_data
    AmazonMwsOrderResponse.new(process({
      "Action"=>"GetOrderReferenceDetails",
      "AmazonOrderReferenceId" => @amazon_order_reference_id,
    }))
  end

  def set_order_data(total, currency)
    process({
      "Action"=>"SetOrderReferenceDetails",
      "AmazonOrderReferenceId" => @amazon_order_reference_id,
      "OrderReferenceAttributes.OrderTotal.Amount" => total,
      "OrderReferenceAttributes.OrderTotal.CurrencyCode" => currency
    })
  end

  def confirm_order
    process({
      "Action"=>"ConfirmOrderReference",
      "AmazonOrderReferenceId" => @amazon_order_reference_id,
    })
  end

  def authorize(authorization_reference_id, total, currency, seller_authorization_note: nil)
    client.authorize(
      @amazon_order_reference_id,
      authorization_reference_id,
      total,
      currency_code: currency,
      transaction_timeout: 0, # 0 is synchronous mode
      capture_now: false,
      seller_authorization_note: seller_authorization_note,
    )
  end

  def get_authorization_details(ref_number)
    process({
      "Action" => "GetAuthorizationDetails",
      "AmazonAuthorizationId" => ref_number
      })
  end

  def capture(auth_number, ref_number, total, currency, seller_capture_note: nil)
    client.capture(
      auth_number,
      ref_number,
      total,
      currency_code: currency,
      seller_capture_note: seller_capture_note
    )
  end

  def get_capture_details(ref_number)
    process({
      "Action" => "GetCaptureDetails",
      "AmazonCaptureId" => ref_number
      })
  end

  def refund(capture_id, ref_number, total, currency)
    process({
      "Action"=>"Refund",
      "AmazonCaptureId" => capture_id,
      "RefundReferenceId" => ref_number,
      "RefundAmount.Amount" => total,
      "RefundAmount.CurrencyCode" => currency
    })
  end

  def get_refund_details(ref_number)
    process({
      "Action" => "GetRefundDetails",
      "AmazonRefundId" => ref_number
      })
  end

  def cancel
    client.cancel_order_reference(@amazon_order_reference_id)
  end

  # Amazon's description:
  # > Call the CloseOrderReference operation to indicate that a previously
  # > confirmed order reference has been fulfilled (fully or partially) and that
  # > you do not expect to create any new authorizations on this order
  # > reference. You can still capture funds against open authorizations on the
  # > order reference.
  # > After you call this operation, the order reference is moved into the
  # > Closed state.
  # https://payments.amazon.com/documentation/apireference/201752000
  def close_order_reference
    client.close_order_reference(@amazon_order_reference_id)
  end

  private

  def default_hash
    {
      "AWSAccessKeyId" => @gateway.preferred_aws_access_key_id,
      "SellerId" => @gateway.preferred_merchant_id,
      "PlatformId"=>"A31NP5KFHXSFV1",
      "SignatureMethod"=>"HmacSHA256",
      "SignatureVersion"=>"2",
      "Timestamp"=>Time.now.utc.iso8601,
      "Version"=>"2013-01-01"
    }
  end

  def process(hash)
    hash = default_hash.reverse_merge(hash)
    query_string = hash.sort.map { |k, v| "#{k}=#{ custom_escape(v) }" }.join("&")
    url = URI.parse(@gateway.api_url)
    message = ["POST", url.hostname, url.path, query_string].join("\n")
    query_string += "&Signature=" + custom_escape(Base64.encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, @gateway.preferred_aws_secret_access_key, message)).strip)
    HTTParty.post(url, :body => query_string)
  end

  def custom_escape(val)
    val.to_s.gsub(/([^\w.~-]+)/) do
      "%" + $1.unpack("H2" * $1.bytesize).join("%").upcase
    end
  end

  def client
    @client ||= PayWithAmazon::Client.new(
      @gateway.preferred_merchant_id,
      @gateway.preferred_aws_access_key_id,
      @gateway.preferred_aws_secret_access_key,
      region: @gateway.preferred_region.to_sym,
      currency_code: @gateway.preferred_currency,
      sandbox: @gateway.preferred_test_mode,
      platform_id: nil, # TODO: Get a platform id for solidus_amazon_payments
    )
  end
end
