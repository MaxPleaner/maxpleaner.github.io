class ApplicationController < ActionController::Base
  def index
    @tracks = session[:tracks]&.map(&:with_indifferent_access) || []

    if @tracks.any?
      sort_by = params[:sort_by] || 'rank'
      sort_direction = params[:sort_direction] || 'asc'

      @tracks = @tracks.sort_by do |track|
        value = track[sort_by]
        if sort_by == 'rank'
          # Convert rank to integer for proper sorting
          value.to_i
        elsif sort_by == 'released'
          # Parse release date, default to earliest date if invalid
          begin
            Date.parse(value.to_s)
          rescue
            Date.new(1900)
          end
        else
          value
        end
      end

      @tracks = @tracks.reverse if sort_direction == 'desc'
    end
  end

  def load_tracks
    require 'sheet_downloader'

    config = SPREADSHEET_CONFIGS[params[:spreadsheet_id]]
    return redirect_to root_path, alert: 'Invalid spreadsheet selection' unless config

    downloader = SheetDownloader.new(
      ENV['GOOGLE_CREDENTIALS_PATH'],
      url: config[:url],
      header_rows: config[:header_rows],
      artist_column: config[:artist_column],
      album_column: config[:album_column]
    )

    session[:tracks] = downloader.download_and_parse
    redirect_to root_path, notice: "Loaded tracks from #{params[:spreadsheet_id]}"
  rescue => e
    Rails.logger.error "Spreadsheet loading error: #{e.message}"
    redirect_to root_path, alert: 'Error loading spreadsheet'
  end

  def lookup_spotify_tracks
    @tracks = session[:tracks]&.map(&:with_indifferent_access) || []

    # Only use limit if checkbox is checked
    tracks_to_process = if params[:use_limit] == '1'
      limit = (params[:limit] || 10).to_i
      @tracks.take(limit)
    else
      @tracks
    end

    total = tracks_to_process.size

    respond_to do |format|
      format.turbo_stream do
        tracks_to_process.each_with_index do |track, index|
          # Search for the album
          albums = RSpotify::Album.search("#{track[:album]} #{track[:artist]}")
          album = albums.first
          if album
            # Store the first result if found
            track[:spotify_album] = {
              uri: album.uri,
              name: album.name,
              artist: album.artists.first.name,
            }
          end

          # Update progress
          turbo_stream.update "progress-bar",
            partial: "progress",
            locals: { current: index + 1, total: total, show_progress: true }
        end

        # Final update to hide progress bar
        turbo_stream.update "progress-bar",
          partial: "progress",
          locals: { current: total, total: total, show_progress: false }
      end

      format.html do
        # Fallback for non-Turbo requests
        tracks_to_process.each do |track|
          albums = RSpotify::Album.search("#{track[:album]} #{track[:artist]}")
          album = albums.first
          next unless album
          track[:spotify_album] = {
            uri: album.uri,
            name: album.name,
            artist: album.artists.first.name,
          }
        end

        session[:tracks] = @tracks
        redirect_to root_path, notice: "Looked up #{tracks_to_process.size} albums on Spotify"
      end
    end
  rescue => e
    Rails.logger.error "Spotify lookup error: #{e.message}"
    redirect_to root_path, alert: 'Error looking up Spotify albums'
  end

  def spotify_login
    # RSpotify handles OAuth2 flow with omniauth
    redirect_to '/auth/spotify'
  end

  def spotify_callback
    # Store the complete auth hash
    session[:spotify_auth] = request.env['omniauth.auth']
    spotify_user = RSpotify::User.new(request.env['omniauth.auth'])
    session[:spotify_user] = spotify_user.to_hash
    redirect_to root_path, notice: 'Successfully connected to Spotify!'
  rescue => e
    Rails.logger.error "Spotify authentication error: #{e.message}"
    redirect_to root_path, alert: 'Failed to connect to Spotify'
  end

  def spotify_logout
    session.delete(:spotify_auth)
    session.delete(:spotify_user)
    redirect_to root_path, notice: 'Successfully disconnected from Spotify'
  end

  def lookup_first_tracks
    @tracks = session[:tracks]&.map(&:with_indifferent_access) || []
    tracks_to_process = @tracks.select { |t| t[:spotify_album].present? }
    total = tracks_to_process.size

    respond_to do |format|
      format.turbo_stream do
        tracks_to_process.each_with_index do |track, index|
          next unless track[:spotify_album]

          # Get the album from Spotify
          album = RSpotify::Album.find(track[:spotify_album][:uri].split(':').last)
          if album
            # Get the first track
            first_track = album.tracks.first
            if first_track
              # Store the first track info
              track[:spotify_first_track] = {
                name: first_track.name,
                uri: first_track.uri,
                duration_ms: first_track.duration_ms
              }
            end
          end

          # Update progress
          turbo_stream.update "progress-bar",
            partial: "progress",
            locals: { current: index + 1, total: total, show_progress: true }
        end

        # Final update to hide progress bar
        turbo_stream.update "progress-bar",
          partial: "progress",
          locals: { current: total, total: total, show_progress: false }
      end

      format.html do
        # Fallback for non-Turbo requests
        tracks_to_process.each do |track|
          next unless track[:spotify_album]

          # Get the album from Spotify
          album = RSpotify::Album.find(track[:spotify_album][:uri].split(':').last)
          next unless album

          # Get the first track
          first_track = album.tracks.first
          next unless first_track

          # Store the first track info
          track[:spotify_first_track] = {
            name: first_track.name,
            uri: first_track.uri,
            duration_ms: first_track.duration_ms
          }
        end

        session[:tracks] = @tracks
        redirect_to root_path, notice: 'First tracks looked up successfully!'
      end
    end

    session[:tracks] = @tracks
  rescue => e
    Rails.logger.error "Spotify track lookup error: #{e.message}"
    redirect_to root_path, alert: 'Error looking up first tracks'
  end

  def create_spotify_playlist
    @tracks = session[:tracks]&.map(&:with_indifferent_access) || []

    # Get track URIs for tracks that have been looked up
    track_uris = @tracks
      .select { |t| t[:spotify_first_track].present? }
      .map { |t| t[:spotify_first_track][:uri] }

    return redirect_to root_path, alert: 'No tracks available to add to playlist' if track_uris.empty?

    # Create a new playlist using the stored auth hash
    return redirect_to root_path, alert: 'Please reconnect your Spotify account' unless session[:spotify_auth]

    playlist_name = params[:playlist_name].presence || 'My Album First Tracks'

    user = RSpotify::User.new(session[:spotify_auth])
    playlist = user.create_playlist!(playlist_name,
      description: 'First tracks from my album collection',
      public: false
    )

    # Add tracks to the playlist (in batches of 100 as per Spotify API limits)
    track_uris.each_slice(100) do |uris_batch|
      playlist.add_tracks!(uris_batch)
    end

    # Store the playlist info for the view
    session[:last_playlist] = {
      url: playlist.external_urls['spotify'],
      name: playlist_name
    }

    redirect_to root_path, notice: "Created playlist '#{playlist_name}' with #{track_uris.size} tracks!"
  rescue => e
    Rails.logger.error "Spotify playlist creation error: #{e.message}"
    redirect_to root_path, alert: 'Error creating Spotify playlist'
  end

  private

  def spotify_user
    @spotify_user ||= session[:spotify_auth] ? RSpotify::User.new(session[:spotify_auth]) : nil
  end
  helper_method :spotify_user
end
