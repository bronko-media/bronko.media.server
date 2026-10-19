# frozen_string_literal: true

require_relative '../../app'

path = File.join(Settings.originals_path, '猫 % [1].png')
long_path = File.join(Settings.originals_path, "#{'long' * 35}.png")
if ARGV.first == 'create'
  MiniMagick.convert { |command| command.size('16x16').xc('red') << 'data/images/fixture.png' }
  File.rename('data/images/fixture.png', path)
  FileUtils.cp(path, long_path)
  BronkoMedia::Indexer.new(settings: Settings, logger: Logger.new(File::NULL)).build_index(
    Settings.originals_path, Settings.thumb_target, Settings.image_extentions
  )
  Image.find_by!(file_path: path).update!(favorite: true, tags: ['猫', 'keep "quoted"'])
end
image = Image.find_by!(file_path: path)
raise 'Favorite or tags lost' unless image.favorite && image.tags == ['猫', 'keep "quoted"']
raise 'Original missing' unless File.file?(path)
raise 'Thumbnail missing' unless File.file?(File.join(Settings.thumb_target, "#{image.md5_path}.png"))

raise 'Long filename lost' unless File.binread(long_path) == File.binread(path)
raise 'Database connection is not encrypted' if ActiveRecord::Base.connection.select_rows(
  "SHOW STATUS LIKE 'Ssl_cipher'"
).first.last.empty?

puts "RESTORED: #{image.md5_path} #{Digest::SHA256.file(path).hexdigest}"
