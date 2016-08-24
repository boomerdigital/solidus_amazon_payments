##
# Amazon Payments - Login and Pay for Spree Commerce
#
# @category    Amazon
# @package     Amazon_Payments
# @copyright   Copyright (c) 2014 Amazon.com
# @license     http://opensource.org/licenses/Apache-2.0  Apache License, Version 2.0
#
##
class Spree::AmazonController < Spree::StoreController
  helper 'spree/orders'
  before_filter :check_current_order
  before_filter :check_amazon_reference_id, only: [:delivery, :complete]

  respond_to :json

  def address
    @amazon_gateway = Spree::Gateway::Amazon.for_currency(current_order.currency)

    current_order.state = 'address'
    current_order.save!
  end

  def payment
    payment = current_order.payments.valid.amazon.first || current_order.payments.create
    payment.number = params[:order_reference]
    payment.payment_method = Spree::Gateway::Amazon.for_currency(current_order.currency)
    payment.source ||= Spree::AmazonTransaction.create(
      order_reference: params[:order_reference],
      order_id: current_order.id
    )

    payment.save!

    render json: {}
  end

  def delivery
    address = SpreeAmazon::Address.find(
      current_order.amazon_order_reference_id,
      gateway: Spree::Gateway::Amazon.for_currency(current_order.currency),
    )

    current_order.state = "address"

    if address
      current_order.email = "pending@amazon.com"
      update_current_order_address!(:ship_address, address)
      update_current_order_address!(:bill_address, address)

      current_order.save!
      current_order.next!

      current_order.reload
      render layout: false
    else
      redirect_to address_amazon_order_path, notice: "Unable to load Address data from Amazon"
    end
  end

  def confirm
    if Spree::OrderUpdateAttributes.new(current_order, checkout_params, request_env: request.headers.env).apply
      while current_order.next
      end

      update_payment_amount!
      current_order.next! unless current_order.confirm?
    else
      render action: :address
    end
  end

  def complete
    @order = current_order
    authorize!(:edit, @order, cookies.signed[:guest_token])
    complete_amazon_order!

    if @order.complete
      @current_order = nil
      flash.notice = Spree.t(:order_processed_successfully)
      redirect_to spree.order_path(@order)
    else
      @order.state = 'cart'
      @order.amazon_transactions.destroy_all
      redirect_to cart_path, notice: "Unable to process order"
    end
  end

  private

  def update_payment_amount!
    payment = current_order.payments.valid.amazon.first
    payment.amount = current_order.total
    payment.save!
  end

  def complete_amazon_order!
    amazon_order = SpreeAmazon::Order.new(
      reference_id: current_order.amazon_order_reference_id,
      total: current_order.total,
      currency: current_order.currency,
      gateway: Spree::Gateway::Amazon.for_currency(current_order.currency)
    )
    amazon_order.save_total
    amazon_order.confirm

    amazon_order.fetch
    current_order.email = amazon_order.email
    update_current_order_address!(:ship_address, amazon_order.address)
  end

  def checkout_params
    params.require(:order).permit(permitted_checkout_attributes)
  end

  def update_current_order_address!(address_type, amazon_address)
    new_address = Spree::Address.new address_attributes(amazon_address)
    new_address.save!

    current_order.send("#{address_type}_id=", new_address.id)
    current_order.save!
  end

  def address_attributes(amazon_address)
    {
      firstname: amazon_address.first_name || "Amazon",
      lastname: amazon_address.last_name || "User",
      address1: amazon_address.address1 || "N/A",
      address2: amazon_address.address2 || "N/A",
      phone: amazon_address.phone || "N/A",
      city: amazon_address.city,
      zipcode: amazon_address.zipcode,
      state_name: amazon_address.state_name,
      country: amazon_address.country
    }
  end

  def check_current_order
    unless current_order
      redirect_to root_path, notice: "No Order Found"
    end
  end

  def check_amazon_reference_id
    unless current_order.amazon_order_reference_id
      flash.now[:notice] = 'No order reference found'
      redirect_to root_path
    end
  end
end
