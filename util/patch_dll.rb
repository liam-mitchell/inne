HOST = "https://dojo.nplusplus.ninja"
PROXY = "45.32.150.168:8126/ctp".ljust(HOST.length, "\x00")

raise "npp.dll not found in folder" if !File.file?('npp.dll')
file = File.binread('npp.dll')
file.include?(HOST) ? file.gsub!(HOST, PROXY) : (
  file.include?(PROXY) ? file.gsub!(PROXY, HOST) : (raise "URL not found")
)
File.binwrite('npp.dllP', file)

