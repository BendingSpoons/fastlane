require_relative '../model'
module Spaceship
  class ConnectAPI
    class AppPriceTier
      include Spaceship::ConnectAPI::Model

      attr_accessor :price_points

      attr_mapping({
        "pricePoints" => "price_points"
       })

      def self.type
        return "appPriceTiers"
      end

      # Note: it is possible to retrieve price points as well, but only up to 50 per tier (10 default)
      def self.all(filter: {}, includes: nil, limit: nil, sort: nil)
        resps = Spaceship::ConnectAPI.get_app_price_tiers(filter: filter, includes: includes, limit: limit, sort: sort).all_pages
        return resps.flat_map(&:to_models)
      end

      def price_points(filter: {}, includes: nil, limit: nil, sort: nil)
        resps = Spaceship::ConnectAPI.get_app_price_points_for_tier(app_price_tier_id: id, filter: filter, includes: includes, limit: limit, sort: sort).all_pages
        return resps.flat_map(&:to_models)
      end
    end
  end
end
