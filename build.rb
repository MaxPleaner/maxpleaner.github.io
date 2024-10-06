require 'slim'
require 'fileutils'
require 'pry'

class SiteBuilder
  PartialData = {}

  # Main entry point. Compiles src/ to dest/
  def self.run
    if ENV["FORCE"] == "true"
      FileUtils.rm_rf("./dist/.", secure: true)
      FileUtils.mkdir_p("./dist/public")
    end

    ["./src/pages", "./src/public"].each do |dir_prefix|
      Dir.glob("#{dir_prefix}/**/*").each do |src|
        dest = src.gsub("/src/", "/dist/").gsub("/pages/", "/")
        if File.directory?(src)
          FileUtils.mkdir_p(dest)
        else
          if dest.end_with?(".slim")
            dest.gsub!(".slim", ".html")
            puts "rendering slim: #{src}"
            render_slim(src, dest)
          else
            puts "copying file: #{src}"
            FileUtils.copy(src, dest)
          end
        end
      end
    end

    puts "~~~ BUILT SITE ~~~"
  end

  # Call this from a view to render another sub view. Second argument is optional partial data e.g. { foo: "bar" }
  def self.partial(src, **data)
    set_partial_data(**data) do
      Tilt.new(src, {pretty: true}).render(self, data)
    end
  end

  class << self
    private

    # Internal method which populates PartialData, calls the block, then empties PartialData
    # This script is single-threaded so using a global works fine.
    def set_partial_data(**data, &blk)
      PartialData.merge!(data)
      result = blk.call
      PartialData.clear
      result
    end

    # Compiles `src` slim file to html and writes to `dest`
    def render_slim(src, dest, **data)
      File.open(dest, "w") do |dest_file|
        rendered_html = partial(src, **data)
        dest_file.write(rendered_html)
      end
    end
  end
end

if __FILE__ == $0
  SiteBuilder.run
end
