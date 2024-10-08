# ---------------------------------------------------------------
# FOR LINUX: you'll need to install inotify-tools first
# inotifywait -m -e modify,create,delete src/ --format '%e %w%f' | xargs -n1 -I {} ./build.rb {}
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# FOR OSX: you'll need to install fswatch first
fswatch -0 src/ | while read -d "" event; do
    echo "WATCH EVENT: $event"
    ruby build.rb "$event"
done
# ---------------------------------------------------------------