require_relative '../model'
module Spaceship
  class ConnectAPI
    class Territory
      include Spaceship::ConnectAPI::Model

      attr_accessor :currency

      attr_mapping({
        "currency" => "currency"
      })

      def self.type
        return "territories"
      end

      #
      # API
      #

      def self.all(client: nil, filter: {}, includes: nil, limit: 180, sort: nil)
        client ||= Spaceship::ConnectAPI
        resps = client.get_territories(filter: {}, includes: nil, limit: nil, sort: nil).all_pages
        return resps.flat_map(&:to_models)
      end

      def self.for_eula(end_user_license_agreement_id: nil)
        resps = Spaceship::ConnectAPI.get_eula_territories(end_user_license_agreement_id: end_user_license_agreement_id).all_pages
        return resps.flat_map(&:to_models)
      end
    end
  end
end
