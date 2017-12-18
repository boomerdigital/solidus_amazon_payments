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
    @response = Hash.from_xml(response.body).fetch("GetOrderReferenceDetailsResponse", {})
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

  def initialize(amazon_order_reference_id, gateway:, address_consent_token: nil)
    @amazon_order_reference_id = amazon_order_reference_id
    @gateway = gateway
    @address_consent_token = address_consent_token
  end


  def fetch_order_data
    AmazonMwsOrderResponse.new(get_order_reference_details)
  end

  # @param total [String] The amount to set on the order
  # @param amazon_options [Hash] These options are forwarded to the underlying
  #   call to PayWithAmazon::Client#set_order_reference_details
  def set_order_reference_details(total, amazon_options={})
    client.set_order_reference_details(
      @amazon_order_reference_id,
      total,
      amazon_options
    )
  end

  def set_order_data(total, currency)
    client.set_order_reference_details(
      @amazon_order_reference_id,
      total,
      currency_code: currency
    )
  end

  def get_order_reference_details
    client.get_order_reference_details(
      @amazon_order_reference_id,
      address_consent_token: @address_consent_token,
    )
  end

  def confirm_order
    client.confirm_order_reference(@amazon_order_reference_id)
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

  def get_authorization_details(auth_id)
    client.get_authorization_details(auth_id)
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

  def get_capture_details(capture_id)
    client.get_capture_details(capture_id)
  end

  def refund(capture_id, ref_number, total, currency, seller_refund_note: nil)
    client.refund(
      capture_id,
      ref_number,
      total,
      currency_code: currency,
      seller_refund_note: seller_refund_note
    )
  end

  def get_refund_details(refund_id)
    client.get_refund_details(refund_id)
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
