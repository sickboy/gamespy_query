require 'teststrap'

context "Base" do
  setup { GamespyQuery::Base.new }

end

context "Funcs" do
  setup { GamespyQuery::Funcs }

  denies("TimeOutError") { topic::TimeOutError.new }.nil

  # TODO: Or should we simply test the Base class who includes this already?
  context "Included" do
    setup { Class.new { include GamespyQuery::Funcs } }

    context "Instance" do
      setup { topic.new }
      # TODO: This method doesnt do anything atm
      asserts("strip_tags") { topic.strip_tags "test" }.equals "test"

      asserts("clean string") { topic.clean "test" }.equals "test"
      asserts("clean integer") { topic.clean "1" }.equals 1
      asserts("clean float") { topic.clean "1.5" }.equals 1.5

      asserts("clean_string") { topic.clean_string("test encoding").encoding }.equals Encoding.find("UTF-8")

      asserts("handle_chr") { topic.handle_chr(25 >> 8) }.equals 0

      asserts("get_string") { topic.get_string("test").encoding }.equals Encoding.find("UTF-8")
    end
  end
end

context "Tools" do
  setup { GamespyQuery::Tools }

  denies("Logger") { topic.logger }.nil

  # TODO: Somehow returns strange string with unescaped double quotes embedded
  asserts("dbg_msg") { topic.dbg_msg Exception.new }.equals "Exception: Exception\nBackTrace: \n(on line 17 in /srv/samba/share/gamespy_query/test/units/base_test.rb)"

  asserts("log_exception") { topic.log_exception Exception.new }.equals true
  asserts("debug") { topic.debug{"test"} }.nil
end
