require_relative '../model'
module Spaceship
  class ConnectAPI
    class InAppPurchase
      include Spaceship::ConnectAPI::Model

      attr_accessor :in_app_purchase_type
      attr_accessor :product_id
      attr_accessor :reference_name
      attr_accessor :state

      # Defines the different in-app purchase product types
      #
      # As specified by Apple: https://developer.apple.com/documentation/appstoreconnectapi/list_all_in-app_purchases_for_an_app
      module IAPType
        # A product that allows users to purchase dynamic content for a set period (auto-rene).
        AUTOMATICALLY_RENEWABLE_SUBSCRIPTION = "AUTOMATICALLY_RENEWABLE_SUBSCRIPTION"
        # A product that is used once
        CONSUMABLE = "CONSUMABLE"
        # This is not properly documented, but is present in the API docs
        FREE_SUBSCRIPTION = "FREE_SUBSCRIPTION"
        # A product that is purchased once and does not expire or decrease with use.
        NON_CONSUMABLE = "NON_CONSUMABLE"
        # A product that allows users to purchase a service with a limited duration.
        NON_RENEWING_SUBSCRIPTION = "NON_RENEWING_SUBSCRIPTION"
      end

      attr_mapping({
                       "inAppPurchaseType" => "in_app_purchase_type",
                       "productId" => "product_id",
                       "referenceName" => "reference_name",
                       "state" => "state"
                   })

      def self.type
        return "inAppPurchases"
      end

      #
      # API
      #

      def self.all(filter: {}, includes: nil, limit: nil, sort: nil)
        resps = Spaceship::ConnectAPI.get_in_app_purchases(filter: filter, includes: includes).all_pages
        return resps.flat_map(&:to_models)
      end
    end
  end
end
