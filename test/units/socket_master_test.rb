require 'teststrap'

context "SocketMaster" do
  DEFAULT_ADDRS = [
      "127.0.0.1:2302",
      "127.0.0.1:2306"
  ]
  setup { GamespyQuery::SocketMaster.new DEFAULT_ADDRS }

  asserts("Process") { topic.process! }.size 2
end
