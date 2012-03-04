require 'teststrap'

context "Socket" do
  DEFAULT_DATA = [
      "\x00\x04\x05\x06\asplitnum\x00\x00\x00gamever\x001.59.79548\x00hostname\x00-=WASP=- Warfare CO (Prime)\x00mapname\x00takistan\x00gametype\x00CTI\x00numplayers\x0046\x00numteams\x000\x00maxplayers\x0054\x00gamemode\x00openplaying\x00timelimit\x0015\x00password\x000\x00param1\x000\x00param2\x000\x00currentVersion\x00159\x00requiredVersion\x00159\x00mod\x00Arma 2;Arma 2: Operation Arrowhead;Arma 2: British Armed Forces (Lite);Arma 2: Private Military Company (Lite)\x00equalModRequired\x000\x00gameState\x007\x00dedicated\x001\x00platform\x00linux\x00language\x0065545\x00difficulty\x002\x00mission\x00[54] Warfare BE V2.069 - Takistan\x00gamename\x00arma2oapc\x00sv_battleye\x001\x00verifySignatures\x001\x00signatures\x00bi;WarFXPE;GLT_ADDONS;warFXsunlight;TGW_Zeroing;trsm_oa;soa110;SMK;jsrsfa;v2ECL;CBA_v0-7-3;ZEU_test;TRSM;TracersWAR;bi2;VopSound;cba_b158;acex_sm;WarFXLighting;gdtmod_plants2;TGW_Thermal;cba_b151;ASR;...\x00modhash\x00PMC v. 1.01;BAF v. 1.02;da39a3ee5e6b4b0d3255bfef95601890afd80709;\x00hash\x00f8c806b971abb935747da3900cab55599c0bc60c\x00\x00\x01player_\x00\x00Skilllos\x00Cool Hand\x00Viktor Reznov\x00Alchemist(HUN)\x00General Heinkel [GER]\x00Max\x00\xD0\x94\xD1\x80\xD0\xBE\xD0\xBD\xD0\xB3\xD0\xBE\x00letchik\x00Angerbode\x00TiDus\x00DrHat\x00Kermit\x00[UaS] snicka\x00Wedel\x00Dnalir [NOR]\x00Davor\x00Cateye(GER)\x00Bamse\x00Jorj\x00POMbI4\x00Daredevil\x00DrSMOKE\x00Vollpfosten\x00Maddin\x00-=[LRRP]=-Sentinel(NL)\x00Husky\x00Scumhawk\x00Bone-CH\x00Jarzah\x00I./KG40_Razor\x00Cpl.Bouiss\x00nAh\x00Tremor\x00Diamm\x00TUROCK_(FR-VODKA)\x00j.moss\x00FOKS\x00Phoenix\x00AfterShave\x00Coupe\x00Mitradis\x00Daniel\x00Flanker\x00Sig\x00_DPVf_hinkel\x00Random Sequence\x00\x00team_\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00Ru\x00SO\x00\x00\x00\x00\x00\x00\x00\x00TF\x00\x00\x00\x00UTGPrivates\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00score_\x00\x00",
      "\x00\x04\x05\x06\asplitnum\x00\x81\x01score_\x00\x00371\x00314\x00335\x0038\x00224\x0036\x0096\x0083\x0042\x00237\x0037\x00137\x00212\x0082\x0041\x0042\x0035\x0073\x0094\x0028\x00127\x0045\x00107\x0030\x00-2\x0083\x002\x0026\x0023\x0034\x0010\x0056\x0016\x006\x0036\x001\x000\x001\x000\x003\x000\x002\x001\x000\x0020\x000\x00\x00deaths_\x00\x0024\x0017\x0018\x0015\x0028\x0025\x0027\x0029\x007\x0010\x008\x0011\x008\x0011\x0016\x0015\x0016\x006\x0010\x0023\x0038\x003\x0017\x003\x002\x007\x002\x001\x004\x0014\x002\x004\x002\x000\x0019\x005\x001\x004\x004\x000\x003\x002\x000\x000\x008\x000\x00\x00\x00\x02\x00"
  ]

  setup { GamespyQuery::Socket.new "127.0.0.1:2302" }

  denies("Confirm valid") { topic.valid? }

  asserts("Set state 3, confirm set") { topic.state = 3; topic.state }.equals 3
  asserts("Set state 5, confirm valid") { topic.state = 5; topic.valid? }

  denies("handle_write") { topic.state = 1; topic.handle_write }
  denies("handle_read") { topic.state = 0; topic.handle_read }

  asserts("handle_write") { topic.state = 0; topic.handle_write }
  asserts("handle_read") { topic.state = 1; topic.handle_read }

  # TODO
  #asserts("handle_exc") { topic.handle_exc }

  asserts("handle_splitnum") { topic.handle_splitnum "" }
  asserts("handle_challenge") { topic.handle_challenge "" }
  asserts("handle_state (Write)") { topic.state = 0; topic.handle_state }
  denies("handle_state (Read)") { topic.state = 1; topic.handle_state }

  asserts("fetch") { topic.fetch }

  asserts("sync") { topic.sync }
  context "Sync custom" do
    setup { topic.sync(DEFAULT_DATA) }
    asserts("Is a hash") { topic }.is_a?(Hash)

    context "Players" do
      setup { topic["players"] }
      asserts("Players defined") { topic }.is_a?(Hash)

      context "Player 0" do
        setup { topic[0] }

        asserts("name") { topic[:name] }.equals "-=[LRRP]=-Sentinel(NL)"
        asserts("team") { topic[:team] }.equals ""
        asserts("score") { topic[:score] }.equals -2
        asserts("deaths") { topic[:deaths] }.equals 2
      end

      context "Player 10" do
        setup { topic[10] }

        asserts("name") { topic[:name] }.equals "Coupe"
        asserts("team") { topic[:team] }.equals ""
        asserts("score") { topic[:score] }.equals 3
        asserts("deaths") { topic[:deaths] }.equals 0
      end

    end
    asserts("Hostname defined") { topic["hostname"] }.is_a?(String)
    asserts("Hostname") { topic["hostname"] }.equals "-=WASP=- Warfare CO (Prime)"
    asserts("Modhash") { topic["modhash"] }.equals "PMC v. 1.01;BAF v. 1.02;da39a3ee5e6b4b0d3255bfef95601890afd80709;"
  end

  # TODO
  context "MultiSocket" do
    setup { GamespyQuery::MultiSocket }

  end
end
