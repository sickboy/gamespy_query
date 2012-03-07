require 'teststrap'
require 'ostruct'

context "Options" do
  context "Parser" do
    setup { GamespyQuery::Options }

    asserts("Default Params") { topic.parse([]) }.raises SystemExit

    asserts("version") { topic.parse(["--version"]) }.raises SystemExit #.equals 0
    asserts("help") { topic.parse(["--help"]) }.raises SystemExit #.equals 0
                                                                        #asserts("no-verbose") { topic.parse([]).options.verbose? }.equals false
    asserts("verbose") { topic.parse(["-v"]) }.raises SystemExit

    context "Commands" do
      asserts("sync") { topic.parse(["sync", "127.0.0.1:2302"]) }.nil
    end

    context "Master" do
      context "Commands" do
        asserts("list") { any_instance_of(GamespyQuery::Master) { |c| mock(c).read { "Test data" } }; topic.parse(["master", "list"]) }.nil
        asserts("process") { any_instance_of(GamespyQuery::Master) { |c| mock(c).process { "Test data" } }; topic.parse(["master", "process"]) }.nil
        asserts("process_master") { mock(GamespyQuery::SocketMaster).process_master("arma2oapc", "") { "Test data" }; topic.parse(["master", "process_master"]) }.nil
      end
    end
  end
end
