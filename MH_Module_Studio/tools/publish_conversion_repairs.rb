# encoding: UTF-8
# Developer-only: publish only native-verified new files; never replace a user SKP.
require 'json'
require 'digest'
require 'fileutils'
require 'securerandom'
require 'time'
require 'csv'

project=File.expand_path('..',__dir__)
staging=File.realpath(ARGV.fetch(0))
destination=File.realpath(ARGV.fetch(1))
commit=ARGV.include?('--publish')
resume=ARGV.include?('--resume')
old_path=File.join(destination,'.conversion/report.json')
old_bytes=File.binread(old_path)
old=JSON.parse(old_bytes.dup)
fresh=JSON.parse(File.read(File.join(staging,'.conversion/report.json'),encoding:'UTF-8'))
native=JSON.parse(File.read(File.join(project,'outputs/conversion-067/native-check.json'),encoding:'UTF-8'))
raise 'Unexpected conversion roots/status' unless old['source']==fresh['source'] && old['total']==227 && fresh['total']==64 && fresh['status']=='complete'
success=fresh['files'].select { |row| row['status']=='converted' }
if resume
  backups=Dir[File.join(destination,'.conversion/report-before-067-*.json')]
  raise 'No matching interrupted publication backup' unless backups.any? { |path| JSON.parse(File.read(path,encoding:'UTF-8'))==old }
end
raise 'Native checks incomplete' unless native['status']=='complete' && native['files'].length==success.length && native['files'].all? { |row| row['status']=='passed' }
raise 'Native files differ' unless native['files'].map { |row| row['relative'] }.sort==success.map { |row| row['relative'] }.sort

inside=lambda do |root,path|
  File.expand_path(path).tr('\\','/').downcase.start_with?(root.tr('\\','/').downcase+'/')
end
old_files=Dir.glob(File.join(destination,'**/*'),File::FNM_DOTMATCH).select { |path| File.file?(path) && File.extname(path).downcase=='.skp' }
if resume
  targets=success.map { |row| File.join(destination,row['relative']) }
  old_files-=targets
end
old_hashes=old_files.to_h { |path| [path,Digest::SHA256.file(path).hexdigest] }
missing_previous=old['files'].select { |row| row['status']=='converted' && !File.file?(File.join(destination,row['relative'])) }.map { |row| row['relative'] }
old['files'].each do |row|
  path=File.join(old['source'],row['relative'])
  raise "Source changed: #{row['relative']}" unless inside.call(old['source'],path) && Digest::SHA256.file(path).hexdigest==row['source_sha256']
end
success.each do |row|
  path=File.join(staging,row['relative']);target=File.join(destination,row['relative'])
  raise 'File escapes conversion roots' unless inside.call(staging,path) && inside.call(destination,target)
  raise "Staging changed: #{row['relative']}" unless row['verified_export'] && row['scale_verified'] && Digest::SHA256.file(path).hexdigest==row['output_sha256']
  if File.exist?(target)
    prior=old['files'].find { |entry| entry['relative']==row['relative'] }
    unless resume && prior && prior['status']=='failed' && Digest::SHA256.file(target).hexdigest==row['output_sha256']
      raise "Destination exists; preserve it: #{target}"
    end
  end
  ancestor=File.dirname(target)
  ancestor=File.dirname(ancestor) until File.exist?(ancestor)
  raise 'Destination symlink escapes root' unless File.realpath(ancestor)==destination || inside.call(destination,File.realpath(ancestor))
end
puts JSON.generate('ready'=>success.length,'existing_skp_retained'=>old_hashes.length,'sources_verified'=>old['files'].length,'publish'=>commit)
exit unless commit

folder=File.join(destination,'.conversion')
backup=File.join(folder,'report-before-067-'+Time.now.utc.strftime('%Y%m%dT%H%M%SZ')+'.json')
File.open(backup,File::WRONLY|File::CREAT|File::EXCL|File::BINARY) { |io| io.write(old_bytes) }
published=[]
success.each do |row|
  source=File.join(staging,row['relative']);target=File.join(destination,row['relative'])
  if resume && File.file?(target)
    raise 'Resumed file changed' unless Digest::SHA256.file(target).hexdigest==row['output_sha256']
    published << row['relative'];next
  end
  FileUtils.mkdir_p(File.dirname(target))
  temporary=File.join(File.dirname(target),'.mh-publish-'+SecureRandom.hex(8)+'.skp')
  begin
    FileUtils.cp(source,temporary)
    raise 'Copy checksum differs' unless Digest::SHA256.file(temporary).hexdigest==row['output_sha256']
    File.link(temporary,target) # Atomic, same volume, fails if a target already exists.
    published << row['relative']
  ensure
    File.delete(temporary) if File.file?(temporary)
  end
end
raise 'Existing library changed' unless old_hashes.all? { |path,sha| File.file?(path) && Digest::SHA256.file(path).hexdigest==sha }
raise 'Report changed during publish' unless File.binread(old_path)==old_bytes

replacements=fresh['files'].to_h { |row| [row['relative'],row] }
merged=Marshal.load(Marshal.dump(old))
merged['files']=old['files'].map do |row|
  replacement=replacements[row['relative']]
  if replacement
    replacement.merge('repair_profile'=>'conversion-067')
  elsif row['status']=='failed'
    row.merge('deferred'=>true,'deferred_reason'=>'Tấm cong/DADX: giữ ngoài phạm vi theo yêu cầu trước đó.')
  else
    row
  end
end
merged['profile']='conversion-067'
merged['converted']=merged['files'].count { |row| row['status']=='converted' }
merged['failed']=merged['files'].count { |row| row['status']=='failed' }
merged['processed']=merged['files'].length
merged['existing']=merged['files'].count { |row| row['status']=='existing' }
merged['repair_pass']={'completed_at'=>Time.now.utc.iso8601,'attempted'=>fresh['total'],'added'=>published.length,
  'native_verified'=>native['files'].length,'deferred'=>merged['files'].count { |row| row['deferred'] },'retained_existing_skp'=>old_hashes.length,
  'present_skp'=>old_hashes.length+published.length,'missing_previous_outputs'=>missing_previous}
known=merged.fetch('known_outputs',{})
success.each { |row| known[row['relative']]=row.slice('relative','status','source_sha256','output_sha256','verified_export') }
merged['known_outputs']=known
temporary=old_path+'.tmp-'+SecureRandom.hex(4)
File.write(temporary,JSON.pretty_generate(merged));FileUtils.mv(temporary,old_path,force:true)
CSV.open(File.join(folder,'report.csv'),'wb',encoding:'bom|utf-8') do |csv|
  csv << %w[file status kind deferred diagnostic]
  merged['files'].each { |row| csv << row.values_at('relative','status','module_kind','deferred','error') }
end

remaining=merged['files'].select { |row| row['status']=='failed' }
lines=['# Kết quả xử lý 96 file lỗi','',
  "Đã bổ sung #{published.length} file vào #{destination}. Kết quả chuyển đổi cộng dồn: #{merged['converted']}/#{merged['total']} nguồn đã chuyển.",
  "Thư mục hiện có #{old_hashes.length+published.length} SKP. Có #{missing_previous.length} bản ghi thành công trước đây không còn file ở đường dẫn cũ; không tự khôi phục hoặc ghi đè các file đó.",
  "Còn #{remaining.length} file: #{merged['repair_pass']['deferred']} tấm cong/DADX đã hoãn; #{remaining.count { |row| !row['deferred'] }} file còn giới hạn công thức/hình học.",
  "Giữ nguyên #{old_hashes.length} SKP đã có và SHA-256 của toàn bộ #{old['files'].length} file nguồn. Các bản bổ sung qua nạp SKP, sửa tham số và Scale lặp lại trong SketchUp.",
  '', '## Các file bổ sung', '', '| File | Loại |', '|---|---|']
success.each { |row| lines << "| #{row['relative']} | #{row['module_kind']=='geometry' ? 'Hình học tĩnh, không có T giả' : 'Parametric từ ATT'} |" }
lines.concat(['','## Chưa chuyển được','','| File | Lý do |','|---|---|'])
remaining.each do |row|
  message=row['deferred'] ? row['deferred_reason'] : row['error']
  lines << "| #{row['relative'].gsub('|','/')} | #{message.to_s.gsub('|','/').gsub(/\s+/,' ')} |"
end
unless missing_previous.empty?
  lines.concat(['','## Bản ghi cũ không còn file tại đường dẫn đã lưu',''])
  missing_previous.each { |name| lines << "- #{name}" }
end
text=lines.join("\n")+"\n"
File.write(File.join(folder,'report.md'),text)
File.write(File.join(project,'outputs/conversion-067/ket-qua-va-file-con-lai.md'),text)
File.write(File.join(project,'outputs/conversion-067/published.json'),JSON.pretty_generate(merged['repair_pass'].merge('published'=>published,'converted'=>merged['converted'],'remaining'=>remaining.length)))
puts JSON.generate('published'=>published.length,'converted'=>merged['converted'],'remaining'=>remaining.length,'backup'=>backup)
