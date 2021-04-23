require_relative '../model'
require_relative '../file_uploader'
require_relative './app_preview_set'
require_relative '../../errors'
require 'spaceship/globals'

require 'digest/md5'

module Spaceship
  class ConnectAPI
    class AppPreview
      include Spaceship::ConnectAPI::Model

      attr_accessor :file_size
      attr_accessor :file_name
      attr_accessor :source_file_checksum
      attr_accessor :preview_frame_time_code
      attr_accessor :mime_type
      attr_accessor :video_url
      attr_accessor :preview_image
      attr_accessor :upload_operations
      attr_accessor :asset_delivery_state
      attr_accessor :upload

      attr_mapping({
        "fileSize" => "file_size",
        "fileName" => "file_name",
        "sourceFileChecksum" => "source_file_checksum",
        "previewFrameTimeCode" => "preview_frame_time_code",
        "mimeType" => "mime_type",
        "videoUrl" => "video_url",
        "previewImage" => "preview_image",
        "uploadOperations" => "upload_operations",
        "assetDeliveryState" => "asset_delivery_state",
        "uploaded" => "uploaded"
      })

      def self.type
        return "appPreviews"
      end

      def awaiting_upload?
        (asset_delivery_state || {})["state"] == "AWAITING_UPLOAD"
      end

      def complete?
        (asset_delivery_state || {})["state"] == "COMPLETE"
      end

      def error?
        (asset_delivery_state || {})["state"] == "FAILED"
      end

      #
      # API
      #

      def self.get(client: nil, app_preview_id: nil)
        client ||= Spaceship::ConnectAPI
        client.get_app_preview(app_preview_id: app_preview_id).first
      end

      # Creates an AppPreview in an AppPreviewSet
      # Setting the optional frame_time_code will force polling until video is done processing
      # @param app_preview_set_id The AppPreviewSet id
      # @param path The path of the file
      # @param frame_time_code The time code for the preview still frame (ex: "00:00:07:01")
      def self.create(client: nil, app_preview_set_id: nil, path: nil)
        require 'faraday'

        client ||= Spaceship::ConnectAPI

        filename = File.basename(path)
        filesize = File.size(path)
        bytes = File.binread(path)

        post_attributes = {
          fileSize: filesize,
          fileName: filename
        }

        # Create placeholder
        begin
          preview = client.post_app_preview(
            app_preview_set_id: app_preview_set_id,
            attributes: post_attributes
          ).first
        rescue Spaceship::InternalServerError => error
          # Sometimes creating a preview with the web session App Store Connect API
          # will result in a false failure. The response will return a 503 but the database
          # insert will eventually go through.
          #
          # When this is observed, we will poll until we find the matching preview that
          # is awaiting for upload and file size
          #
          # The equivalent for the screenshots: https://github.com/fastlane/fastlane/pull/16842
          time = Time.now.to_i

          timeout_minutes = (ENV["SPACESHIP_PREVIEW_UPLOAD_TIMEOUT"] || 20).to_i

          loop do
            puts("Waiting for preview to appear before uploading...")
            sleep(30)

            previews = Spaceship::ConnectAPI::AppPreviewSet
                       .get(app_preview_set_id: app_preview_set_id)
                       .app_previews

            preview = previews.find do |p|
              p.awaiting_upload? && p.file_size == filesize
            end

            break if preview

            time_diff = Time.now.to_i - time
            raise error if time_diff >= (60 * timeout_minutes)
          end
        end

        # Upload the file
        upload_operations = preview.upload_operations
        Spaceship::ConnectAPI::FileUploader.upload(upload_operations, bytes)

        # Update file uploading complete
        patch_attributes = {
          previewFrameTimeCode: "00:00:00:00",
          uploaded: true,
          sourceFileChecksum: Digest::MD5.hexdigest(bytes)
        }

        begin
          preview = client.patch_app_preview(
            app_preview_id: preview.id,
            attributes: patch_attributes
          ).first
        rescue => error
          puts("Failed to patch app preview. Update may have gone through so verifying") if Spaceship::Globals.verbose?

          preview = Spaceship::ConnectAPI::AppPreview.get(client: client, app_preview_id: preview.id)
          raise error unless preview.complete?
        end

        preview
      end

      def self.wait_for_processing(app_preview_id: nil, frame_time_code: nil)
        loop do
          preview = Spaceship::ConnectAPI::AppPreview.get(client: client, app_preview_id: app_preview_id)
          unless preview.video_url.nil?
            puts("Preview processing complete!") if Spaceship::Globals.verbose?
            break if frame_time_code.nil?
            preview.update(attributes: {
                previewFrameTimeCode: frame_time_code
            })
            puts("Updated preview frame time code!") if Spaceship::Globals.verbose?
            break
          end

          sleep_time = 30
          puts("Waiting #{sleep_time} seconds before checking status of processing...") if Spaceship::Globals.verbose?
          sleep(sleep_time)
        end
      end

      def update(client: nil, attributes: nil)
        client ||= Spaceship::ConnectAPI
        attributes = reverse_attr_mapping(attributes)
        client.patch_app_preview(app_preview_id: id, attributes: attributes).first
      end

      def delete!(client: nil, filter: {}, includes: nil, limit: nil, sort: nil)
        client ||= Spaceship::ConnectAPI
        client.delete_app_preview(app_preview_id: id)
      end
    end
  end
end
