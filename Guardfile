# vim: ft=ruby
# More info at https://github.com/guard/guard#readme

guard :rspec, cmd: "bundle exec rspec" do
  watch(%r{^spec/})
  watch(%r{^scripts/(.*)[.]lic}) { |m| "spec/#{m[1]}" }
  watch(%r{^type_data/}) { system('bin/migrate') and 'spec/gameobj-data/' }
end
