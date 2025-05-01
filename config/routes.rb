Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root 'application#index'
  post 'load_tracks', to: 'application#load_tracks'
  post 'lookup_spotify_tracks', to: 'application#lookup_spotify_tracks'
  post 'lookup_first_tracks', to: 'application#lookup_first_tracks'
  post 'create_spotify_playlist', to: 'application#create_spotify_playlist'
  delete 'spotify_logout', to: 'application#spotify_logout'

  # Spotify OAuth routes
  get '/auth/spotify/callback', to: 'application#spotify_callback'
  get '/auth/failure', to: redirect('/')
end
