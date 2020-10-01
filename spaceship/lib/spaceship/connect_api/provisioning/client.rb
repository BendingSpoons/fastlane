require_relative '../api_client'
require_relative './provisioning'
require_relative '../../portal/portal_client'

module Spaceship
  class ConnectAPI
    module Provisioning
      class Client < Spaceship::ConnectAPI::APIClient
        def initialize(cookie: nil, current_team_id: nil, token: nil, another_client: nil)
          another_client ||= Spaceship::Portal.client if cookie.nil? && token.nil?

          super(cookie: cookie, current_team_id: current_team_id, token: token, another_client: another_client)

          self.extend(Spaceship::ConnectAPI::Provisioning::API)
          self.provisioning_request_client = self
        end

        def self.hostname
          'https://api.appstoreconnect.apple.com/v1'
        end
      end
    end
  end
end
