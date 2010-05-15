VER = '0.0.12'
TAGNAME = "release-#{VER}"
DIST = "idleserver-#{VER}"

desc 'Run test suite'
task :test do
  system('cd client && rake test')
end

desc 'Build distribution files for new release'
#task :dist => [:tag, :test] do
task :dist do
  rm_rf(DIST)
  mkdir(DIST)
  system("git archive master | tar -C #{DIST} -x")
  File.delete("#{DIST}/Rakefile")  # Don't need this file in the distribution
  File.open("#{DIST}/VERSION", 'w') do |verfile|
    verfile.puts(VER)
  end
  system("tar czf #{DIST}.tar.gz #{DIST}")
  rm_rf(DIST)
  system("openssl md5 #{DIST}.tar.gz > #{DIST}.tar.gz.md5")
  system("openssl sha1 #{DIST}.tar.gz > #{DIST}.tar.gz.sha1")
  system("gpg --detach --armor #{DIST}.tar.gz")
end

desc 'Tag a new release'
task :tag do
  system("git tag -a #{TAGNAME}")
end

desc 'Clean up distribution files and work directories'
task :clean do
  rm(Dir.glob('idleserver-*.tar.gz*'))
  rm_rf(DIST)
end

