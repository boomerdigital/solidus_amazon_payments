require 'spec_helper'

describe SpreeAmazon::Address do
  let(:gateway) { create(:amazon_gateway) }

  describe '.find' do
    it "returns a new address if the order has a Physical address" do
      address_data = build_address_response(
        "City"=>"Topeka",
        "StateOrRegion"=>"KS",
        "PostalCode"=>"66615",
        "CountryCode"=>"US",
        "Phone"=>"800-000-0000",
        "Name"=>"Mary Jones",
        "AddressLine1"=>"4409 Main St.",
        "AddressLine2"=>"Suite 2"
      )
      stub_amazon_response("ORDER_REFERENCE", address_data)

      address = SpreeAmazon::Address.find("ORDER_REFERENCE", gateway: gateway)

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

      address = SpreeAmazon::Address.find("ORDER_REFERENCE", gateway: gateway)

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
    stub_request(
      :post,
      'https://mws.amazonservices.com/OffAmazonPayments_Sandbox/2013-01-01',
    ).with(
      body: hash_including(
        'Action' => 'GetOrderReferenceDetails'
      )
    ).to_return(
      {
        headers: {'content-type' => 'text/xml'},
        body: response_data,
      },
    )
  end

  def build_address_response(address_details)
    <<-XML.strip_heredoc
      <GetOrderReferenceDetailsResponse
    xmlns="http://mws.amazonservices.com/
          schema/OffAmazonPayments/2013-01-01">
        <GetOrderReferenceDetailsResult>
          <OrderReferenceDetails>
            <AmazonOrderReferenceId>P01-1234567-1234567</AmazonOrderReferenceId>
            <CreationTimestamp>2012-11-05T20:21:19Z</CreationTimestamp>
            <ExpirationTimestamp>2013-05-07T23:21:19Z</ExpirationTimestamp>
            <OrderReferenceStatus>
              <State>Open</State>
            </OrderReferenceStatus>
            <Destination>
              <DestinationType>Physical</DestinationType>
              <PhysicalDestination>
                #{address_details.nil? ? nil : address_details.to_xml.split("<hash>\n  ").last.split("</hash>\n").first}
              </PhysicalDestination>
            </Destination>
            <ReleaseEnvironment>Live</ReleaseEnvironment>
          </OrderReferenceDetails>
        </GetOrderReferenceDetailsResult>
        <ResponseMetadata>
          <RequestId>5f20169b-7ab2-11df-bcef-d35615e2b044</RequestId>
        </ResponseMetadata>
      </GetOrderReferenceDetailsResponse>
    XML
  end
end
