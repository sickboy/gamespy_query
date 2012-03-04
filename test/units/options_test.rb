require 'teststrap'

context "Options" do
  setup { GamespyQuery::Options }

end

require 'teststrap'
require 'ostruct'

context "Options" do
  context "Parser" do
    setup { GamespyQuery::Options }

    asserts("returns an OpenStruct") { topic.parse.is_a?(OpenStruct) }
    asserts("tasks is Array") { topic.parse.tasks.is_a?(Array) }

    asserts("verbose") { topic.parse(["-v"]).verbose }.equals true
    asserts("no-verbose") { topic.parse(["--no-verbose"]).verbose }.equals false

    # TODO: How to test the exit properly?
    asserts("version") { mock(GamespyQuery::Options).exit { 0 }; topic.parse(["--version"])} #.equals 0
    asserts("help") { mock(GamespyQuery::Options).exit { 0 }; topic.parse(["--help"]) } #.equals 0

    #asserts("init") { topic.parse(["--init"]).tasks }.same_elements [[:init, Dir.pwd]]
  end
end
