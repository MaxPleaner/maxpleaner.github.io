require 'google_drive'
require 'logger'

class SheetDownloader
  def initialize(credentials_path, url:, header_rows: 1, artist_column: 2, album_column: 3, limit: nil)
    @credentials_path = credentials_path
    @spreadsheet_url = url
    @header_rows = header_rows
    @artist_column = artist_column
    @album_column = album_column
    @limit = limit
    @logger = Logger.new(STDOUT)
  end

  def download_and_parse
    @logger.info("Initializing Google Drive session...")
    session = GoogleDrive::Session.from_service_account_key(@credentials_path)

    @logger.info("Accessing spreadsheet...")
    spreadsheet = session.spreadsheet_by_url(@spreadsheet_url)
    worksheet = spreadsheet.worksheets.first

    @logger.info("Parsing data...")
    data = []

    # Start after header rows
    start_row = @header_rows + 1
    max_row = @limit ? start_row + @limit : worksheet.num_rows

    (start_row..max_row).each do |row|
      row_data = {
        artist: worksheet[row, @artist_column],
        album: worksheet[row, @album_column]
      }

      # Add any additional columns that exist
      row_data[:rank] = worksheet[row, 1] if worksheet[row, 1].present?
      row_data[:released] = worksheet[row, 4] if worksheet[row, 4].present?
      row_data[:label] = worksheet[row, 5] if worksheet[row, 5].present?
      row_data[:genre] = worksheet[row, 6] if worksheet[row, 6].present?
      row_data[:votes] = worksheet[row, 7] if worksheet[row, 7].present?
      row_data[:avg] = worksheet[row, 8] if worksheet[row, 8].present?
      row_data[:wavg] = worksheet[row, 9] if worksheet[row, 9].present?

      data << row_data if row_data[:artist].present? && row_data[:album].present?
    end

    @logger.info("Successfully parsed #{data.size} rows")
    data
  rescue StandardError => e
    @logger.error("Error downloading/parsing sheet: #{e.message}")
    raise
  end
end
