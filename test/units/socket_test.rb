require 'teststrap'

context "Socket" do
  setup { GamespyQuery::Socket.new "127.0.0.1:2302" }

end
