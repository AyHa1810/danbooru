# frozen_string_literal: true

# @see Source::URL::Twitter
module Sources::Strategies
  class Twitter < Base
    # List of hashtag suffixes attached to tag other names
    # Ex: 西住みほ生誕祭2019 should be checked as 西住みほ
    # The regexes will not match if there is nothing preceding
    # the pattern to avoid creating empty strings.
    COMMON_TAG_REGEXES = [
      /(?<!\A)生誕祭(?:\d*)\z/,
      /(?<!\A)誕生祭(?:\d*)\z/,
      /(?<!\A)版もうひとつの深夜の真剣お絵描き60分一本勝負(?:_\d+)?\z/,
      /(?<!\A)版深夜の真剣お絵描き60分一本勝負(?:_\d+)?\z/,
      /(?<!\A)版深夜の真剣お絵かき60分一本勝負(?:_\d+)?\z/,
      /(?<!\A)深夜の真剣お絵描き60分一本勝負(?:_\d+)?\z/,
      /(?<!\A)版深夜のお絵描き60分一本勝負(?:_\d+)?\z/,
      /(?<!\A)版真剣お絵描き60分一本勝(?:_\d+)?\z/,
      /(?<!\A)版お絵描き60分一本勝負(?:_\d+)?\z/
    ]

    def self.enabled?
      Danbooru.config.twitter_api_key.present? && Danbooru.config.twitter_api_secret.present?
    end

    def domains
      ["twitter.com", "twimg.com"]
    end

    def site_name
      "Twitter"
    end

    def image_urls
      # https://pbs.twimg.com/media/EBGbJe_U8AA4Ekb.jpg:orig
      if parsed_url.image_url?
        [parsed_url.orig_image_url]
      elsif api_response.present?
        api_response.dig(:extended_entities, :media).to_a.map do |media|
          if media[:type] == "photo"
            media[:media_url_https] + ":orig"
          elsif media[:type].in?(["video", "animated_gif"])
            variants = media.dig(:video_info, :variants)
            videos = variants.select { |variant| variant[:content_type] == "video/mp4" }
            video = videos.max_by { |v| v[:bitrate].to_i }
            video[:url]
          end
        end
      else
        [url]
      end
    end

    def preview_urls
      if api_response.dig(:extended_entities, :media).present?
        api_response.dig(:extended_entities, :media).to_a.map do |media|
          media[:media_url_https] + ":small"
        end
      else
        image_urls.map do |url|
          url.gsub(/:orig\z/, ":small")
        end
      end
    end

    def page_url
      return nil if status_id.blank? || tag_name.blank?
      "https://twitter.com/#{tag_name}/status/#{status_id}"
    end

    def profile_url
      return nil if tag_name.blank?
      "https://twitter.com/#{tag_name}"
    end

    def intent_url
      user_id = api_response.dig(:user, :id_str)
      return nil if user_id.blank?
      "https://twitter.com/intent/user?user_id=#{user_id}"
    end

    def profile_urls
      [profile_url, intent_url].compact
    end

    def tag_name
      if tag_name_from_url.present?
        tag_name_from_url
      elsif api_response.present?
        api_response.dig(:user, :screen_name)
      else
        ""
      end
    end

    def artist_name
      if api_response.present?
        api_response.dig(:user, :name)
      else
        tag_name
      end
    end

    def artist_commentary_title
      ""
    end

    def artist_commentary_desc
      api_response[:full_text].to_s
    end

    def normalize_for_artist_finder
      profile_url.try(:downcase).presence || url
    end

    def normalize_for_source
      if tag_name_from_url.present? && status_id.present?
        "https://twitter.com/#{tag_name_from_url}/status/#{status_id}"
      elsif status_id.present?
        "https://twitter.com/i/web/status/#{status_id}"
      elsif url =~ %r{\Ahttps?://(?:o|image-proxy-origin)\.twimg\.com/\d/proxy\.jpg\?t=(\w+)&}i
        str = Base64.decode64($1)
        source = URI.extract(str, %w[http https])
        if source.any?
          source = source[0]
          if source =~ %r{^https?://twitpic.com/show/large/[a-z0-9]+}i
            source.gsub!(%r{show/large/}, "")
            index = source.rindex(".")
            source = source[0..index - 1]
          end
          source
        end
      end
    end

    def tags
      api_response.dig(:entities, :hashtags).to_a.map do |hashtag|
        [hashtag[:text], "https://twitter.com/hashtag/#{hashtag[:text]}"]
      end
    end

    def normalize_tag(tag)
      COMMON_TAG_REGEXES.each do |rg|
        norm_tag = tag.gsub(rg, "")
        if norm_tag != tag
          return norm_tag
        end
      end
      tag
    end

    def dtext_artist_commentary_desc
      return "" if artist_commentary_desc.blank?

      url_replacements = api_response.dig(:entities, :urls).to_a.map do |obj|
        [obj[:url], obj[:expanded_url]]
      end
      url_replacements += api_response.dig(:extended_entities, :media).to_a.map do |obj|
        [obj[:url], ""]
      end
      url_replacements = url_replacements.to_h

      desc = artist_commentary_desc.unicode_normalize(:nfkc)
      desc = CGI.unescapeHTML(desc)
      desc = desc.gsub(%r{https?://t\.co/[a-zA-Z0-9]+}i, url_replacements)
      desc = desc.gsub(/#([^[:space:]]+)/, '"#\\1":[https://twitter.com/hashtag/\\1]')
      desc = desc.gsub(/@([a-zA-Z0-9_]+)/, '"@\\1":[https://twitter.com/\\1]')
      desc.strip
    end

    def api_client
      TwitterApiClient.new(Danbooru.config.twitter_api_key, Danbooru.config.twitter_api_secret)
    end

    def api_response
      return {} unless self.class.enabled? && status_id.present?
      api_client.status(status_id)
    end

    def status_id
      parsed_url.status_id || parsed_referer&.status_id
    end

    def tag_name_from_url
      parsed_url.twitter_username || parsed_referer&.twitter_username
    end

    memoize :api_response
  end
end
