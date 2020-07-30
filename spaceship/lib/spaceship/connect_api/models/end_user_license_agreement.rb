require_relative '../model'
module Spaceship
  class ConnectAPI
    class EndUserLicenseAgreement
      include Spaceship::ConnectAPI::Model

      attr_accessor :agreement_text

      attr_mapping({
        "agreementText" => "agreement_text"
      })

      def self.type
        return "endUserLicenseAgreements"
      end

      #
      # API
      #

      def fetch_territories
        resp = Spaceship::ConnectAPI.get_eula_territories(end_user_license_agreement_id: id)
        return resp.to_models
      end

      def update(attributes: nil, territory_ids: nil)
        attributes = reverse_attr_mapping(attributes)
        Spaceship::ConnectAPI.patch_end_user_license_agreement(end_user_license_agreement_id: id, attributes: attributes, territory_ids: territory_ids)
      end

      def delete!
        Spaceship::ConnectAPI.delete_end_user_license_agreement(end_user_license_agreement_id: id)
      end
    end
  end
end
