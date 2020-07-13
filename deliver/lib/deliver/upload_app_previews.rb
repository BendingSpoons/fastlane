require 'parallel'
require 'spaceship/tunes/tunes'
require 'digest/md5'

require_relative 'app_preview'
require_relative 'module'
require_relative 'loader'
require_relative 'utils'

module Deliver
  # upload app previews to App Store Connect
  class UploadAppPreviews
    def upload(options, previews, max_n_threads = 16)
      return if options[:skip_app_previews]
      return if options[:edit_live]

      legacy_app = options[:app]
      app_id = legacy_app.apple_id
      app = Spaceship::ConnectAPI::App.get(app_id: app_id)

      platform = Spaceship::ConnectAPI::Platform.map(options[:platform])
      version = app.get_edit_app_store_version(platform: platform)
      UI.user_error!("Could not find a version to edit for app '#{app.name}' for '#{platform}'") unless version

      UI.important("Will begin uploading app previews for '#{version.version_string}' on App Store Connect")

      UI.message("Starting with the upload of app previews...")
      previews_per_language = previews.group_by(&:language)

      localizations = version.get_app_store_version_localizations

      if options[:overwrite_app_previews]
        # Get localizations on version
        n_threads = [max_n_threads, localizations.length].min
        Parallel.each(localizations, in_threads: n_threads) do |localization|
          # Only delete app previews if trying to upload
          next unless previews_per_language.keys.include?(localization.locale)

          # Iterate over all app previews for each set and delete
          previews_sets = localization.get_app_preview_sets

          # Multi threading delete on single localization
          previews_sets.each do |preview_set|
            UI.message("Removing all previously uploaded app previews for '#{localization.locale}' '#{preview_set.preview_type}'...")
            preview_set.app_previews.each do |preview|
              Deliver.retry_api_call do
                UI.verbose("Deleting app preview - #{localization.locale} #{preview_set.preview_type} #{preview.id}")
                preview.delete!
              end
            end
          end
        end
      end

      # Finding languages to enable
      languages = previews_per_language.keys
      locales_to_enable = languages - localizations.map(&:locale)

      if locales_to_enable.count > 0
        lng_text = "language"
        lng_text += "s" if locales_to_enable.count != 1
        Helper.show_loading_indicator("Activating #{lng_text} #{locales_to_enable.join(', ')}...")

        locales_to_enable.each do |locale|
          version.create_app_store_version_localization(attributes: {
              locale: locale
          })
        end

        Helper.hide_loading_indicator

        # Refresh version localizations
        localizations = version.get_app_store_version_localizations
      end

      upload_app_previews(previews_per_language, localizations, options, max_n_threads)
    end

    def upload_app_previews(previews_per_language, localizations, options, max_n_threads)
      # Check if should wait for processing
      # Default to waiting if submitting for review (since needed for submission)
      # Otherwise use enviroment variable
      if ENV["DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING"].nil?
        wait_for_processing = options[:submit_for_review]
        UI.verbose("Setting wait_for_processing from ':submit_for_review' option")
      else
        UI.verbose("Setting wait_for_processing from 'DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING' environment variable")
        wait_for_processing = !FastlaneCore::Env.truthy?("DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING")
      end

      if wait_for_processing
        UI.important("Will wait for screenshot image processing")
        UI.important("Set env DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING=true to skip waiting for screenshots to process")
      else
        UI.important("Skipping the wait for screenshot image processing (which may affect submission)")
        UI.important("Set env DELIVER_SKIP_WAIT_FOR_SCREENSHOT_PROCESSING=false to wait for screenshots to process")
      end

      # Upload app previews
      indized = {} # per language and device type

      n_threads = [max_n_threads, previews_per_language.length].min
      Parallel.each(previews_per_language, in_threads: n_threads) do |language, previews_for_language|
        # Find localization to upload app previews to
        localization = localizations.find do |l|
          l.locale == language
        end

        unless localization
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        indized[localization.locale] ||= {}

        # Create map to find app preview set to add app preview to
        app_preview_sets_map = {}
        app_preview_sets = localization.get_app_preview_sets
        app_preview_sets.each do |app_preview_set|
          app_preview_sets_map[app_preview_set.preview_type] = app_preview_set

          # Set initial app previews count
          indized[localization.locale][app_preview_set.preview_type] ||= {
              count: app_preview_set.app_previews.size,
              checksums: []
          }

          checksums = app_preview_set.app_previews.map(&:source_file_checksum).uniq
          indized[localization.locale][app_preview_set.preview_type][:checksums] = checksums
        end

        UI.message("Uploading #{previews_for_language.length} app previews for language #{language}")
        previews_for_language.each do |preview|
          Deliver.retry_api_call do
            display_type = preview.device_type
            set = app_preview_sets_map[display_type]

            if display_type.nil?
              UI.error("Error... App preview size #{preview.screen_size} not valid for App Store Connect")
              next
            end

            unless set
              set = localization.create_app_preview_set(attributes: {
                  previewType: display_type
              })
              app_preview_sets_map[display_type] = set

              indized[localization.locale][set.preview_type] = {
                  count: 0,
                  checksums: []
              }
            end

            index = indized[localization.locale][set.preview_type][:count]

            if index >= 3
              UI.error("Too many app previews found for device '#{preview.formatted_name}' in '#{preview.language}', skipping this one (#{preview.path})")
              next
            end

            bytes = File.binread(preview.path)
            checksum = Digest::MD5.hexdigest(bytes)
            duplicate = indized[localization.locale][set.preview_type][:checksums].include?(checksum)

            if duplicate
              UI.message("Previous uploaded. Skipping '#{preview.path}'...")
            else
              indized[localization.locale][set.preview_type][:count] += 1
              UI.message("Uploading '#{preview.path}'...")
              set.upload_preview(path: preview.path, wait_for_processing: wait_for_processing)
            end
          end
        end
      end
      UI.success("Successfully uploaded app previews to App Store Connect")
    end

    # helper method so Spaceship::Tunes.client.available_languages is easier to test
    def self.available_languages
      if Helper.test?
        FastlaneCore::Languages::ALL_LANGUAGES
      else
        Spaceship::Tunes.client.available_languages
      end
    end
  end
end
