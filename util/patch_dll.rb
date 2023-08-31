HOST = "https://dojo.nplusplus.ninja"
PROXY = "45.32.150.168:8126/ctp".ljust(HOST.length, "\x00")

fn = ARGV[0] || 'npp.dll'
raise "#{fn} not found in folder" if !File.file?(fn)
file = File.binread(fn)
file.include?(HOST) ? file.gsub!(HOST, PROXY) : (
  file.include?(PROXY) ? file.gsub!(PROXY, HOST) : (raise "URL not found")
)
File.binwrite(fn + 'P', file)

