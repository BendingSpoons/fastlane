require 'parallel'
require 'spaceship/tunes/tunes'
require 'digest/md5'

require_relative 'app_preview'
require_relative 'module'
require_relative 'loader'
require_relative 'utils'

module Deliver
  # upload app previews to App Store Connect
  class BSPUploadAppPreviews
    def upload(options, previews, max_n_threads = 16)
      return if options[:skip_app_previews]
      return if options[:edit_live]

      app = options[:app]

      platform = Spaceship::ConnectAPI::Platform.map(options[:platform])
      version = app.get_edit_app_store_version(platform: platform)
      UI.user_error!("Could not find a version to edit for app '#{app.name}' for '#{platform}'") unless version

      UI.important("Will begin uploading app previews for '#{version.version_string}' on App Store Connect")

      UI.message("Starting with the upload of app previews...")
      candidate_previews_per_language = previews.group_by(&:language)

      localizations = version.get_app_store_version_localizations

      app_store_preview_sets_map = load_app_store_preview_sets(localizations)

      changed_sets_per_language = get_changed_previews(localizations, app_store_preview_sets_map, candidate_previews_per_language)
      app_store_previews_to_delete = get_app_store_previews_to_delete(app_store_preview_sets_map, changed_sets_per_language)

      delete_app_previews(localizations, app_store_preview_sets_map, app_store_previews_to_delete, max_n_threads)

      # Finding languages to enable
      languages = candidate_previews_per_language.keys
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

      upload_app_previews(changed_sets_per_language, localizations, options, max_n_threads)
    end

    def load_app_store_preview_sets(localizations)
      app_store_preview_sets_map = {}

      localizations.each do |localization|
        app_store_sets_for_language = {}
        app_store_preview_sets = localization.get_app_preview_sets
        app_store_preview_sets.each do |app_store_preview_set|
          app_store_sets_for_language[app_store_preview_set.preview_type] = app_store_preview_set
        end

        app_store_preview_sets_map[localization.locale] = app_store_sets_for_language
      end

      app_store_preview_sets_map
    end

    def get_changed_previews(localizations, app_store_preview_sets_map, candidate_previews_per_language)
      candidate_sets_per_language = {} # per locale and type; all provided previews
      changed_sets_per_language = {} # per locale and type; previews that have been added, removed or updated

      # first, divide the new previews into sets
      candidate_previews_per_language.each do |language, candidates_for_language|
        candidates_per_preview_type = {}

        candidates_for_language.each do |candidate_preview|
          preview_type = candidate_preview.device_type

          if preview_type.nil?
            UI.error("Error... Preview size #{candidate_preview.screen_size} not valid for App Store Connect")
            next
          end

          bytes = File.binread(candidate_preview.path)
          checksum = Digest::MD5.hexdigest(bytes)

          candidates_per_preview_type[preview_type] ||= []
          candidates_per_preview_type[preview_type] << {
              preview: candidate_preview,
              checksum: checksum
          }
        end

        candidate_sets_per_language[language] = candidates_per_preview_type
      end

      # remove any duplicate by comparing checksums, keep the first occurrence only
      candidate_sets_per_language.values.each do |candidate_sets_per_preview_type|
        candidate_sets_per_preview_type.values.each do |candidates_with_checksums|
          candidates_with_checksums.uniq! { |preview| preview[:checksum] }
        end
      end

      # then, compare the new previews with the existing ones
      candidate_sets_per_language.each do |language, candidate_sets_per_preview_type|
        # Find localization to upload app previews to
        localization = localizations.find do |l|
          l.locale == language
        end

        unless localization
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        changed_previews_per_type = {}

        unless app_store_preview_sets_map.key?(language)
          UI.error("Couldn't find localization on version for #{language}")
          next
        end

        app_store_sets_per_preview_type = app_store_preview_sets_map[language]
        candidate_sets_per_preview_type.each do |preview_type, candidates_with_checksums|
          app_store_preview_set = app_store_sets_per_preview_type[preview_type]

          unless app_store_preview_set
            app_store_preview_set = localization.create_app_preview_set(attributes: {
                previewType: preview_type
            })
            # the app_previews field of a newly created set tends to be nil, when it should be []
            app_store_preview_set.app_previews ||= []
            app_store_sets_per_preview_type[preview_type] = app_store_preview_set
          end

          app_store_previews = app_store_preview_set.app_previews

          changed_previews_per_type[preview_type] ||= []

          candidates_with_checksums.each_with_index do |candidate_with_checksum, index|
            if index >= 3
              UI.error("Too many previews found for device '#{preview_type}' in '#{language}', skipping this one (#{candidate_with_checksum[:preview].path})")
              next
            end

            app_store_preview = app_store_previews[index]
            next unless app_store_preview.nil? || app_store_preview.source_file_checksum != candidate_with_checksum[:checksum]

            # the added and updated previews from the candidates
            changed_previews_per_type[preview_type] << {
                preview: candidate_with_checksum[:preview],
                position: index
            }
          end

          # if there are more (existing) app store previews, it means some need to be removed without being replaced
          next unless app_store_previews.size > candidates_with_checksums.size

          index = candidates_with_checksums.size
          while index < app_store_previews.size
            # add a "nil" preview for every position that will no longer be filled (in order to delete them)
            changed_previews_per_type[preview_type] << {
                preview: nil,
                position: index
            }
            index += 1
          end
        end

        changed_sets_per_language[language] = changed_previews_per_type

        count = changed_previews_per_type.values.reduce(0) { |sum, previews_with_positions| sum + previews_with_positions.size }
        UI.message("Found #{count} added, removed or updated previews for language #{language}")
      end

      changed_sets_per_language
    end

    def get_app_store_previews_to_delete(app_store_preview_sets_map, changed_sets_per_language)
      previews_to_delete = {} # per language and preview type

      changed_sets_per_language.each do |language, changed_sets_per_preview_type|
        previews_to_delete_per_preview_type = {}
        app_store_sets_per_preview_type = app_store_preview_sets_map[language]

        app_store_sets_per_preview_type.values.each do |app_store_preview_set|
          preview_type = app_store_preview_set.preview_type

          unless changed_sets_per_preview_type.key?(preview_type)
            # if there is no preview type specified, add empty array of previews to delete
            previews_to_delete_per_preview_type[preview_type] = {
                previews: [],
                count_after_delete: app_store_preview_set.app_previews.size
            }
            next
          end

          changed_preview_set = changed_sets_per_preview_type[preview_type]
          changed_preview_positions = changed_preview_set.map { |preview_with_position| preview_with_position[:position] }
          previews_to_delete_for_preview_type = []

          app_store_preview_set.app_previews.each_with_index do |preview, index|
            next unless changed_preview_positions.include?(index)
            previews_to_delete_for_preview_type << preview
          end

          previews_to_delete_per_preview_type[preview_type] = {
              previews: previews_to_delete_for_preview_type,
              count_after_delete: app_store_preview_set.app_previews.size - previews_to_delete_for_preview_type.size
          }
        end

        previews_to_delete[language] = previews_to_delete_per_preview_type
      end

      previews_to_delete
    end

    def get_expected_count_after_delete(app_store_previews_to_delete)
      sum = 0

      app_store_previews_to_delete.values.each do |previews_per_preview_type|
        previews_per_preview_type.values.each do |preview_with_count|
          sum += preview_with_count[:count_after_delete]
        end
      end

      sum
    end

    def delete_app_previews(localizations, app_store_preview_sets_map, app_store_previews_to_delete, max_n_threads, tries: 5)
      tries -= 1

      # Multi threading delete on single localization
      n_threads = [max_n_threads, localizations.length].min
      Parallel.each(localizations, in_threads: n_threads) do |localization|
        language = localization.locale

        next unless app_store_previews_to_delete.key?(language)

        # Find all the previews that need to be deleted (via their ID) and delete them
        app_store_sets_per_preview_type = app_store_preview_sets_map[language]

        app_store_sets_per_preview_type.values.each do |app_store_preview_set|
          preview_type = app_store_preview_set.preview_type
          previews_to_delete_per_preview_type = app_store_previews_to_delete[language]

          # Skip if there are no specified previews to delete for the given locale and preview type
          next unless previews_to_delete_per_preview_type.key?(preview_type)
          previews_to_delete_for_preview_type = previews_to_delete_per_preview_type[preview_type][:previews]
          UI.message("Removing #{previews_to_delete_for_preview_type.size} previews for '#{language}' '#{preview_type}'...")

          ids_to_delete = previews_to_delete_for_preview_type.map(&:id)

          app_store_preview_set.app_previews.each do |app_store_preview|
            next unless ids_to_delete.include?(app_store_preview.id)

            UI.message("Deleting app preview - #{language} #{app_store_preview_set.preview_type} #{app_store_preview.id}")
            Deliver.retry_api_call do
              app_store_preview.delete!
              UI.message("Deleted app preview - #{language} #{app_store_preview_set.preview_type} #{app_store_preview.id}")
            end
          end
        end
      end

      # Verify all specified previews have been deleted
      # Sometimes API requests will fail but previews will still be deleted
      # Also, need to reload the sets to get the actual previews in App Store after the deletion
      reloaded_app_store_sets_map = load_app_store_preview_sets(localizations)
      actual_count = count_previews(reloaded_app_store_sets_map, app_store_previews_to_delete)
      expected_count = get_expected_count_after_delete(app_store_previews_to_delete)
      count = actual_count - expected_count
      UI.important("Number of previews not deleted: #{count}")
      if count > 0
        if tries.zero?
          UI.user_error!("Failed verification of all app previews deleted... #{count} app preview(s) still exist")
        else
          UI.error("Failed to delete all app previews... Tries remaining: #{tries}")
          delete_app_previews(localizations, reloaded_app_store_sets_map, app_store_previews_to_delete, max_n_threads, tries: tries)
        end
      else
        UI.message("Successfully deleted all previews")
      end
    end

    def count_previews(app_store_preview_sets_map, app_store_previews_to_delete)
      count = 0

      app_store_preview_sets_map.each do |language, app_store_sets_for_language|
        # disregard count for language if nothing is deleted in it
        next unless app_store_previews_to_delete.key?(language)

        app_store_sets_for_language.values.each do |app_store_set_for_preview_type|
          count += app_store_set_for_preview_type.app_previews.size
        end
      end

      count
    end

    def upload_app_previews(changed_sets_per_language, localizations, options, max_n_threads)
      # Check if should wait for processing
      # Default to waiting if submitting for review (since needed for submission)
      # Otherwise use environment variable
      if ENV["DELIVER_SKIP_WAIT_FOR_PREVIEW_PROCESSING"].nil?
        wait_for_processing = options[:submit_for_review]
        UI.verbose("Setting wait_for_processing from ':submit_for_review' option")
      else
        UI.verbose("Setting wait_for_processing from 'DELIVER_SKIP_WAIT_FOR_PREVIEW_PROCESSING' environment variable")
        wait_for_processing = !FastlaneCore::Env.truthy?("DELIVER_SKIP_WAIT_FOR_PREVIEW_PROCESSING")
      end

      if wait_for_processing
        UI.important("Will wait for preview video processing")
        UI.important("Set env DELIVER_SKIP_WAIT_FOR_PREVIEW_PROCESSING=true to skip waiting for previews to process")
      else
        UI.important("Skipping the wait for preview video processing (which may affect submission)")
        UI.important("Set env DELIVER_SKIP_WAIT_FOR_PREVIEW_PROCESSING=false to wait for previews to process")
      end

      frame_time_code = options[:frame_time_code]

      # need to reload the sets after the delete operations
      app_store_preview_sets_map = load_app_store_preview_sets(localizations)

      n_threads = [max_n_threads, changed_sets_per_language.keys.length].min
      Parallel.each(changed_sets_per_language, in_threads: n_threads) do |language, changed_sets_per_preview_type|
        app_store_sets_for_language = app_store_preview_sets_map[language]
        uploaded_app_store_previews_per_preview_type = {}

        changed_sets_per_preview_type.each do |preview_type, changed_previews_for_preview_type|
          changed_previews_to_be_uploaded = changed_previews_for_preview_type.reject { |preview_with_position| preview_with_position[:preview].nil? }
          UI.message("Uploading #{changed_previews_to_be_uploaded.length} app previews for '#{language}', '#{preview_type}'")

          uploaded_app_store_previews = []

          changed_previews_to_be_uploaded.each do |changed_preview_with_position|
            changed_preview = changed_preview_with_position[:preview]

            # don't upload the empty previews that represent the no-longer filled positions
            next if changed_preview.nil?

            position = changed_preview_with_position[:position]
            app_store_preview_set = app_store_sets_for_language[preview_type]

            Deliver.retry_api_call do
              UI.message("Uploading '#{changed_preview.path}'...")
              # wait_for_processing is set to false and frame_time_code to nil since the waiting will be done later
              uploaded_app_store_previews << app_store_preview_set.upload_preview(path: changed_preview.path, wait_for_processing: false, position: position)
            end
          end

          uploaded_app_store_previews_per_preview_type[preview_type] = uploaded_app_store_previews
        end

        uploaded_app_store_previews_per_preview_type.each do |preview_type, uploaded_app_store_previews|
          uploaded_app_store_previews.each do |uploaded_app_store_preview|
            Deliver.retry_api_call do
              # add a random waiting time between calls in order not to overwhelm the Apple API
              sleep(Random.rand(0..3))

              UI.message("Waiting for #{uploaded_app_store_preview.id} for '#{language}', '#{preview_type}' to finish processing")
              Spaceship::ConnectAPI::AppPreview.do_wait_for_processing(app_preview_id: uploaded_app_store_preview.id, frame_time_code: frame_time_code)
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
