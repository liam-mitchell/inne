require 'fileutils'
#require 'tk'
require 'win32/registry'

MAPPACK = 'HaxPack'
NAME = 'hax'
HOST = 'https://dojo.nplusplus.ninja'
PORT = 8126
PROXY = '45.32.150.168'
TARGET = "#{PROXY}:#{PORT}/#{NAME}".ljust(HOST.length, "\x00")

def log_exception(e, msg)
=begin
  Tk::messageBox(
    type:    'ok', 
    title:   'Error',
    message:  "#{msg}\n\nDetails: #{e}",
    icon:    'error'
  )
  $root.destroy
=end
  puts "#{msg}\n\nDetails: #{e}"
end

def find_steam_folders
  # Find Steam directory in the registry
  folder = nil
  folder = Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\WOW6432Node\Valve\Steam') rescue nil
  folder = (Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Valve\Steam') rescue nil) if folder.nil?
  raise "Steam folder not found in registry" if folder.nil?

  # Find Steam installation path in the registry
  path = folder['InstallPath'] rescue nil
  raise "Steam installation path not found in registry" if path.nil?
  raise "Steam installation not found" if !Dir.exist?(path)

  # Find steamapps folder
  steamapps = File.join(path, 'steamapps')
  raise "Steam folder not found (steamapps folder missing)" if !Dir.exist?(steamapps)
  library = File.read(File.join(steamapps, 'libraryfolders.vdf')) rescue nil
  raise "Steam folder not found (libraryfolders.vdf file missing)" if library.nil?

  # Find alternative Steam installation paths
  folders = library.split("\n").select{ |l| l =~ /"path"/i }.map{ |l| l[/"path".*"(.+)"/, 1].gsub(/\\\\/, '\\') rescue nil }.compact
  folders << path
  folders.uniq!

  folders
rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to find Steam folder")
end

def find_npp_folder
  folder = nil
  find_steam_folders.each{ |f|
    path = File.join(f, 'steamapps', 'common', 'N++')
    folder = path if Dir.exist?(path)
  }
  raise "N++ installation not found" if folder.nil?
  
  folder
rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to find N++ folder.")
end

def find_npp_library
  # Read main library file
  folder = find_npp_folder
  fn = File.join(folder, 'npp.dll')
  raise "N++ files not found (npp.dll missing)" if !File.file?(fn)

  fn
rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to find N++ files.")
end

def patch(depatch = false, info = false)
  # Read main library file
  fn = find_npp_library
  file = File.binread(fn)
  return !file[/#{HOST}/] if info

  # Patch library
  raise "Failed to patch N++ files (incorrect target length)" if TARGET.length != HOST.length
  file = depatch ? file.gsub!(TARGET, HOST) : file.gsub!(HOST, TARGET)
  raise "Failed to patch N++ files (host/target not found)" if file.nil?
  File.binwrite(fn, file)

rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to patch N++ files.")
end

def depatch
  patch(true)
end

def change_levels(install = true)
  # Find folder
  folder = File.join(find_npp_folder, 'NPP', 'Levels')
  raise "N++ levels folder not found" if !Dir.exist?(folder)
  
  # Change file
  fn = install ? 'SI.txt' : 'SI_original.txt'
  FileUtils.cp_r(fn, File.join(folder, 'SI.txt'), remove_destination: true)

rescue RuntimeError => e
  log_exception('', e)
rescue => e
  log_exception(e, "Failed to change level files.")
end

def install
  patch
  change_levels(true)
  puts "Installed #{MAPPACK} successfully!"
end

def uninstall
  depatch
  change_levels(false)
  puts "Uninstalled #{MAPPACK} successfully!"
end

system "mode con: cols=40 lines=2"
installed = patch(false, true)
installed ? uninstall : install
gets

=begin
# Main window
$root = TkRoot.new(title: "")
w, h = 200, 50
$root.minsize(w, h)
$root.geometry("#{w}x#{h}")
$root.grid_columnconfigure(0, weight: 1)
$root.resizable(0, 0)
screen_width = $root.winfo_screenwidth
screen_height = $root.winfo_screenheight
x = (screen_width - w) / 2
y = (screen_height - h) / 2
$root.geometry("#{$root.width}x#{$root.height}+#{x}+#{y}")
Tk.bell

# Elements
label = TkLabel.new($root, text: "#{MAPPACK} #{installed ? "uninstalled" : "installed"} successfully!").grid(row: 0, column: 0, sticky: 'news')
button = TkButton.new($root, text: "Ok", command: -> { $root.destroy }).grid(row: 1, column: 0)

# Run GUI
Tk.mainloop
=end