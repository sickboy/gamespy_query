require 'teststrap'
require 'ostruct'

context "Options" do
  context "Parser" do
    setup { GamespyQuery::Options }

    context "Default params" do
      setup { topic.parse }
      asserts("returns an OpenStruct") { topic.is_a?(OpenStruct) }
      asserts("tasks is Array") { topic.tasks.is_a?(Array) }
    end

    context "Specific params" do
      asserts("verbose") { topic.parse(["-v"]).verbose }.equals true
      asserts("no-verbose") { topic.parse(["--no-verbose"]).verbose }.equals false

      # TODO: How to test the exit properly?
      asserts("version") { mock(GamespyQuery::Options).exit { 0 }; topic.parse(["--version"])} #.equals 0
      asserts("help") { mock(GamespyQuery::Options).exit { 0 }; topic.parse(["--help"]) } #.equals 0

      asserts("sync tasks") { topic.parse(["--sync", "127.0.0.1:2302"]).tasks }.same_elements [:sync]
      asserts("sync argv") { topic.parse(["--sync", "127.0.0.1:2302"]).argv }.same_elements ["127.0.0.1:2302"]
    end
  end
end

context "MasterOptions" do
  setup { GamespyQuery::MasterOptions }

  context "Default params" do
    setup { topic.parse }
    asserts("returns an OpenStruct") { topic.is_a?(OpenStruct) }
    asserts("tasks is Array") { topic.tasks.is_a?(Array) }
  end

  context "Specific params" do
    asserts("verbose") { topic.parse(["-v"]).verbose }.equals true
    asserts("no-verbose") { topic.parse(["--no-verbose"]).verbose }.equals false

    # TODO: How to test the exit properly?
    asserts("version") { mock(GamespyQuery::MasterOptions).exit { 0 }; topic.parse(["--version"])} #.equals 0
    asserts("help") { mock(GamespyQuery::MasterOptions).exit { 0 }; topic.parse(["--help"]) } #.equals 0

    asserts("list") { topic.parse(["--list"]).tasks }.same_elements [:list]

    asserts("process") { topic.parse(["--process"]).tasks }.same_elements [:process]
    asserts("process_master") { topic.parse(["--process_master"]).tasks }.same_elements [:process_master]
  end
end
