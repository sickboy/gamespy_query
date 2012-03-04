require 'teststrap'

context "Master" do
  setup { GamespyQuery::Master.new }

  asserts("geoip_path") { topic.geoip_path }.equals File.join(Dir.pwd, "config")

  asserts("read returns a hash") { topic.read }.is_a?(Hash)

  asserts("process returns a hash") { topic.process }.is_a?(Hash)

  asserts("get_params returns a string") { topic.get_params }.is_a?(String)

  asserts("handle_data") { topic.handle_data "127.0.0.1:2302\n127.0.0.1:2305" }.same_elements ["127.0.0.1:2302", "127.0.0.1:2305"]

  asserts("to_hash") { topic.handle_data "127.0.0.1:2302\n127.0.0.1:2305" }.is_a?(Hash)
end
