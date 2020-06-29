require 'parallel'
require 'spaceship/tunes/tunes'
require 'digest/md5'

require_relative 'app_screenshot'
require_relative 'module'
require_relative 'loader'

module Deliver
  MAX_N_THREADS = 16
  MAX_RETRIES = 10

  # upload screenshots to App Store Connect
  class UploadScreenshots
    def upload(options, screenshots, max_n_threads = MAX_N_THREADS)
      return if options[:skip_screenshots]
      return if options[:edit_live]

      legacy_app = options[:app]
      app_id = legacy_app.apple_id
      app = Spaceship::ConnectAPI::App.get(app_id: app_id)

      platform = Spaceship::ConnectAPI::Platform.map(options[:platform])
      version = app.get_edit_app_store_version(platform: platform)
      UI.user_error!("Could not find a version to edit for app '#{app.name}' for '#{platform}'") unless version

      UI.important("Will begin uploading snapshots for '#{version.version_string}' on App Store Connect")

      UI.message("Starting with the upload of screenshots...")
      screenshots_per_language = screenshots.group_by(&:language)

      localizations = version.get_app_store_version_localizations

      if options[:overwrite_screenshots]
        # Get localizations on version
        n_threads = [max_n_threads, localizations.length].min
        Parallel.each(localizations, in_threads: n_threads) do |localization|
          # Only delete screenshots if trying to upload
          next unless screenshots_per_language.keys.include?(localization.locale)

          # Iterate over all screenshots for each set and delete
          screenshot_sets = localization.get_app_screenshot_sets

          # Multi threading delete on single localization
          threads = []
          errors = []

          screenshot_sets.each do |screenshot_set|
            UI.message("Removing all previously uploaded screenshots for '#{localization.locale}' '#{screenshot_set.screenshot_display_type}'...")
            screenshot_set.app_screenshots.each do |screenshot|
              retry_api_call do
                UI.verbose("Deleting screenshot - #{localization.locale} #{screenshot_set.screenshot_display_type} #{screenshot.id}")
                screenshot.delete!
              end
            end
          end
        end
      end

      # Finding languages to enable
      languages = screenshots_per_language.keys
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

      upload_screenshots(screenshots_per_language, localizations)
    end

    def upload_screenshots(screenshots_per_language, localizations)
      # Upload screenshots
      indized = {} # per language and device type

      n_threads = [max_n_threads, screenshots_per_language.length].min
      Parallel.each(screenshots_per_language, in_threads: n_threads) do |language, screenshots_for_language|
        # Find localization to upload screenshots to
        localization = localizations.find do |l|
          l.locale == language
        end

        unless localization
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        indized[localization.locale] ||= {}

        # Create map to find screenshot set to add screenshot to
        app_screenshot_sets_map = {}
        app_screenshot_sets = localization.get_app_screenshot_sets
        app_screenshot_sets.each do |app_screenshot_set|
          app_screenshot_sets_map[app_screenshot_set.screenshot_display_type] = app_screenshot_set

          # Set initial screnshot count
          indized[localization.locale][app_screenshot_set.screenshot_display_type] ||= {
            count: app_screenshot_set.app_screenshots.size,
            checksums: []
          }

          checksums = app_screenshot_set.app_screenshots.map(&:source_file_checksum).uniq
          indized[localization.locale][app_screenshot_set.screenshot_display_type][:checksums] = checksums
        end

        UI.message("Uploading #{screenshots_for_language.length} screenshots for language #{language}")
        screenshots_for_language.each do |screenshot|
          retry_api_call do
            display_type = screenshot.device_type
            set = app_screenshot_sets_map[display_type]

            if display_type.nil?
              UI.error("Error... Screenshot size #{screenshot.screen_size} not valid for App Store Connect")
              next
            end

            unless set
              set = localization.create_app_screenshot_set(attributes: {
                  screenshotDisplayType: display_type
              })
              app_screenshot_sets_map[display_type] = set

              indized[localization.locale][set.screenshot_display_type] = {
                count: 0,
                checksums: []
              }
            end

            index = indized[localization.locale][set.screenshot_display_type]

            if index >= 10
              UI.error("Too many screenshots found for device '#{screenshot.formatted_name}' in '#{screenshot.language}', skipping this one (#{screenshot.path})")
              next
            end

            bytes = File.binread(screenshot.path)
            checksum = Digest::MD5.hexdigest(bytes)
            duplicate = indized[localization.locale][set.screenshot_display_type][:checksums].include?(checksum)

            if duplicate
              UI.message("Previous uploaded. Skipping '#{screenshot.path}'...")
            else
              indized[localization.locale][set.screenshot_display_type][:count] += 1
              UI.message("Uploading '#{screenshot.path}'...")
              set.upload_screenshot(path: screenshot.path)
            end
          end
        end
      end
      UI.success("Successfully uploaded screenshots to App Store Connect")
    end

    def collect_screenshots(options)
      return [] if options[:skip_screenshots]
      return collect_screenshots_for_languages(options[:screenshots_path], options[:ignore_language_directory_validation])
    end

    def collect_screenshots_for_languages(path, ignore_validation)
      screenshots = []
      extensions = '{png,jpg,jpeg}'

      available_languages = UploadScreenshots.available_languages.each_with_object({}) do |lang, lang_hash|
        lang_hash[lang.downcase] = lang
      end

      Loader.language_folders(path, ignore_validation).each do |lng_folder|
        language = File.basename(lng_folder)

        # Check to see if we need to traverse multiple platforms or just a single platform
        if language == Loader::APPLE_TV_DIR_NAME || language == Loader::IMESSAGE_DIR_NAME
          screenshots.concat(collect_screenshots_for_languages(File.join(path, language), ignore_validation))
          next
        end

        files = Dir.glob(File.join(lng_folder, "*.#{extensions}"), File::FNM_CASEFOLD).sort
        next if files.count == 0

        framed_screenshots_found = Dir.glob(File.join(lng_folder, "*_framed.#{extensions}"), File::FNM_CASEFOLD).count > 0

        UI.important("Framed screenshots are detected! 🖼 Non-framed screenshot files may be skipped. 🏃") if framed_screenshots_found

        language_dir_name = File.basename(lng_folder)

        if available_languages[language_dir_name.downcase].nil?
          UI.user_error!("#{language_dir_name} is not an available language. Please verify that your language codes are available in iTunesConnect. See https://developer.apple.com/library/content/documentation/LanguagesUtilities/Conceptual/iTunesConnect_Guide/Chapters/AppStoreTerritories.html for more information.")
        end

        language = available_languages[language_dir_name.downcase]

        files.each do |file_path|
          is_framed = file_path.downcase.include?("_framed.")
          is_watch = file_path.downcase.include?("watch")

          if framed_screenshots_found && !is_framed && !is_watch
            UI.important("🏃 Skipping screenshot file: #{file_path}")
            next
          end

          screenshots << AppScreenshot.new(file_path, language)
        end
      end

      # Checking if the device type exists in spaceship
      # Ex: iPhone 6.1 inch isn't supported in App Store Connect but need
      # to have it in there for frameit support
      unaccepted_device_shown = false
      screenshots.select! do |screenshot|
        exists = !screenshot.device_type.nil?
        unless exists
          UI.important("Unaccepted device screenshots are detected! 🚫 Screenshot file will be skipped. 🏃") unless unaccepted_device_shown
          unaccepted_device_shown = true

          UI.important("🏃 Skipping screenshot file: #{screenshot.path} - Not an accepted App Store Connect device...")
        end
        exists
      end

      return screenshots
    end

    def retry_api_call
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

          raise Spaceship::TunesClient::ITunesConnectPotentialServerError.new, "Giving up!" if try_number > MAX_RETRIES
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
