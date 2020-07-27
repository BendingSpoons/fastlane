require_relative '../client'
require_relative '../../tunes/tunes_client'

module Spaceship
  class ConnectAPI
    module Users
      class Client < Spaceship::ConnectAPI::Client
        def self.instance
          # Verify there is a token or a client that can be used
          if Spaceship::ConnectAPI.token
            if @client.nil? || @client.token != Spaceship::ConnectAPI.token
              @client = Client.new(token: Spaceship::ConnectAPI.token)
            end
          elsif Spaceship::Tunes.client
            # BSP: Avoid re-using the same client to prevents silent session expiration
            @client = Client.client_with_authorization_from(Spaceship::Tunes.client)
          end

          # Need to handle not having a client but this shouldn't ever happen
          raise "Please login using `Spaceship::Tunes.login('user', 'password')`" unless @client

          @client
        end

        def self.hostname
          'https://appstoreconnect.apple.com/iris/v1/'
        end
      end
    end
  end
end
