require 'spec_helper'

describe SpreeAmazon::Address do
  describe '.find' do
    it "returns a new address if the order has a Physical address" do
      address_data = build_address_response(
        "StateOrRegion"=>"KS",
        "Phone"=>"800-000-0000",
        "City"=>"Topeka",
        "CountryCode"=>"US",
        "PostalCode"=>"66615",
        "Name"=>"Mary Jones",
        "AddressLine1"=>"4409 Main St.",
        "AddressLine2"=>"Suite 2"
      )
      stub_amazon_response("ORDER_REFERENCE", address_data)

      address = SpreeAmazon::Address.find("ORDER_REFERENCE")

      expect(address).to_not be_nil
      expect(address.city).to eq("Topeka")
      expect(address.country_code).to eq("US")
      expect(address.state_name).to eq("KS")
      expect(address.name).to eq("Mary Jones")
      expect(address.address1).to eq("4409 Main St.")
      expect(address.address2).to eq("Suite 2")
      expect(address.phone).to eq("800-000-0000")
    end

    it "returns nil if the order doesn't have a physical address" do
      address_data = build_address_response(nil)
      stub_amazon_response("ORDER_REFERENCE", address_data)

      address = SpreeAmazon::Address.find("ORDER_REFERENCE")

      expect(address).to be_nil
    end
  end

  describe "#first_name" do
    it "returns the first name" do
      address = SpreeAmazon::Address.new(name: "Peter Parker")

      expect(address.first_name).to eq("Peter")
    end
  end

  describe "#last_name" do
    it "returns the last name(s)" do
      address = SpreeAmazon::Address.new(name: "Scott Summers")

      expect(address.last_name).to eq("Summers")
    end
  end

  describe '#country' do
    it "returns the Spree::Country that matches country_code" do
      us = create(:country, iso: 'US')
      address = SpreeAmazon::Address.new(country_code: 'US')

      expect(address.country).to eq(us)
    end
  end

  def stub_amazon_response(order_reference, response_data)
    Spree::Gateway::Amazon.create!(name: 'Amazon', preferred_test_mode: true)
    mws = instance_double(AmazonMws)
    response = AmazonMwsOrderResponse.new(response_data)
    allow(mws).to receive(:fetch_order_data).and_return(response)
    allow(AmazonMws).to receive(:new).with(order_reference, true)
                                     .and_return(mws)
  end

  def build_address_response(address_details)
    {
      "GetOrderReferenceDetailsResponse" =>{
        "GetOrderReferenceDetailsResult"=> {
          "OrderReferenceDetails"=> {
            "OrderReferenceStatus"=> {
              "LastUpdateTimestamp"=>"2016-04-18T17:05:52.621Z", "State"=>"Open"
            },
            "Destination"=> {
              "DestinationType"=>"Physical",
              "PhysicalDestination"=> address_details
            },
            "ExpirationTimestamp"=>"2016-10-15T17:05:32.272Z",
            "IdList"=>{"member"=>"S01-4301752-9080047-A018166"},
            "SellerOrderAttributes"=>nil,
            "OrderTotal"=>{"CurrencyCode"=>"USD", "Amount"=>"29.14"},
            "Buyer"=>{"Name"=>"Joe Doe", "Email"=>"joe@doe.com"},
            "ReleaseEnvironment"=>"Sandbox",
            "AmazonOrderReferenceId"=>"S01-4301752-9080047",
            "CreationTimestamp"=>"2016-04-18T17:05:32.272Z",
            "RequestPaymentAuthorization"=>"false"
          }
        },
        "ResponseMetadata"=>{"RequestId"=>"f390f7fb-0cdc-486c-974b-0db919cf82b3"}
      }
    }
  end
end
