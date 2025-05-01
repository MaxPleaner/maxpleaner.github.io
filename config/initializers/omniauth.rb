require 'rspotify/oauth'

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :spotify, ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'],
    scope: 'user-read-email playlist-modify-public playlist-modify-private user-library-read user-library-modify',
    redirect_uri: ENV['SPOTIFY_REDIRECT_URI']
end

OmniAuth.config.allowed_request_methods = [:post, :get]
