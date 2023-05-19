TEST = true
TARGET = "https://dojo.nplusplus.ninja"
HOST_TEST = "127.0.0.1"
HOST = "45.32.150.168"

def find_lib
  paths = {
    'windows' => "",
    'linux'   => "#{Dir.home}/.steam/steam/steamapps/common/N++/lib64/libnpp.so"
  }
  sys = 'linux'
  paths[sys]
end

def patch
  path = find_lib
  new_lib = IO.binread(find_lib).gsub!(TARGET, PROXY)
  new_lib.nil? ? puts("Didn't find URL") : IO.binwrite(find_lib, new_lib)
end

def depatch
  path = find_lib
  new_lib = IO.binread(find_lib).gsub!(PROXY, TARGET)
  new_lib.nil? ? puts("Didn't find URL") : IO.binwrite(find_lib, new_lib)
end

case ARGV.size
when 0, 1
  puts "Missing args"
when 2, 3
  port = ARGV[1].to_i
  pack = ARGV[2].nil? ? '' : '/' + ARGV[2]
  if port.to_s != ARGV[1] || port <= 1024 || port >= 65536
    puts "Incorrect port"
    exit
  end
  proxy = "#{TEST ? HOST_TEST : HOST}:#{port}#{pack}"
  if proxy.length > TARGET.length
    puts "Mappack name is too long"
    exit
  end
  PROXY = proxy.ljust(TARGET.length, "\x00")
  case ARGV[0]
  when 'p'
    patch
  when 'd'
    depatch
  else
    puts "Incorrect option"
  end
else
  puts "Too many args"
end