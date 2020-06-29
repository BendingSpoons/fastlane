require 'spaceship/tunes/tunes'

require_relative 'module'

module Deliver
  MAX_RETRIES = 10

  def self.retry_api_call
    success = false
    try_number = 0

    until success
      begin
        yield
        success = true
      rescue Spaceship::InternalServerError, Faraday::ConnectionFailed => e
        # BSP: We're not quite sure of what's causing the 500/504 errors, possibly a server issue. To avoid the
        # complete failure of the upload, we retry and hope for the best
        UI.error("Error while interacting with App Store Connect API, making a new attempt. Error: #{e.message}. Counter: #{try_number}")
        try_number += 1

        raise Spaceship::TunesClient::ITunesConnectPotentialServerError.new, "Number of retries exceeded, aborting." if try_number > MAX_RETRIES
      rescue Spaceship::UnexpectedResponse => e
        # If we get this error, it means the previous deletion operation completed successfully and must not be
        # attempted again. We never get this on a failed creation.
        if e.message =~ /The specified resource does not exist/
          success = true
        else
          raise e
        end
      end
    end
  end
end
