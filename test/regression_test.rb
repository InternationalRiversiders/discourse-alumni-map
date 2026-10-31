# frozen_string_literal: true
abort 'Disposable database only' unless ENV['RIVER_DISPOSABLE']=='1' && GlobalSetting.db_name=='river_community_test'
require 'minitest/autorun'
class AlumniMapTest < Minitest::Test
  def setup
    a=DiscourseAlumniMap
    tables=a::Record.connection.tables.grep(/\Ariver_alumni_map_/)
    a::Record.connection.execute('TRUNCATE '+tables.map { |t| a::Record.connection.quote_table_name(t) }.join(',')+' RESTART IDENTITY CASCADE')
    @group=Group.find_or_create_by!(name:'river_test_members')
    @admin=make_user('river_admin',admin:true);@alice=make_user('river_alice');@bob=make_user('river_bob');@carol=make_user('river_carol');@stranger=make_user('river_stranger')
    [@alice,@bob,@carol].each { |u| @group.add(u);u.reload }
    SiteSetting.alumni_map_enabled=true;SiteSetting.alumni_map_read_only=false
    SiteSetting.alumni_map_allowed_groups=@group.id.to_s;SiteSetting.alumni_map_admin_groups=''
  end
  def state(app,user=@alice,query={}) = app::Service.state(user,query.deep_stringify_keys)
  def make_user(name,admin:false)
    User.find_by(username:name) || User.create!(username:name,email:"#{name}-#{SecureRandom.hex(6)}@example.com",password:SecureRandom.hex(32),active:true,approved:true,admin:admin)
  end
  def command(app,user,op,data={},key:SecureRandom.uuid)
    app::Shared.command(user,op,data.deep_stringify_keys,key) { app::Service.call(user,op,data.deep_stringify_keys) }
  end
  def map_data
    {nickname:'匿名校友',country:'中国',city:'成都',latitude:'30.67',longitude:'104.08',published:true,show_username:false,bio:'校友名片'}
  end
  def http(user=nil)
    session=ActionDispatch::Integration::Session.new(Rails.application);session.host! 'community.test';session.https!
    headers={}
    if user
      key=ApiKey.create!(user_id:user.id,created_by_id:@admin.id,description:'isolated community test')
      headers={'Api-Key'=>key.key,'Api-Username'=>user.username}
    end
    [session,headers]
  end
  def test_map_precision_publication_and_moderation
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data)
    profile=a::Profile.first
    assert_equal '30.75',profile.latitude.to_s('F')
    assert_equal '104.0',profile.longitude.to_s('F')
    public_state=state(a,@bob)
    refute_includes public_state.to_json,@alice.username
    command(a,@admin,'moderate',{id:profile.id,status:'hidden',reason:'需要核实'})
    command(a,@alice,'save',map_data.merge(bio:'更新'))
    assert_equal 'hidden',profile.reload.status
    assert_empty state(a,@bob)[:cards]
    command(a,@admin,'moderate',{id:profile.id,status:'visible',reason:'核实完成'})
    assert_empty state(a,@bob)[:cards]
    command(a,@alice,'save',map_data)
    assert_equal 1,state(a,@bob)[:cards].size
    assert_raises(a::Error) { command(a,@alice,'save',map_data.merge(latitude:'NaN')) }
  end
  def test_map_locationless_legacy_profiles_and_complete_public_fields
    a=DiscourseAlumniMap
    original=map_data.merge(city:'',latitude:'',longitude:'',admission_year:'2018',graduation_year:'2022',industry:'教育')
    command(a,@alice,'save',original)
    profile=a::Profile.find_by!(user_id:@alice.id)
    assert_nil profile.latitude
    assert_equal 1,state(a,@bob)[:cards].size
    assert_empty state(a,@bob)[:map][:points]
    fields=state(a,@bob)[:cards].first[:profile_fields]
    assert_includes fields,{label:'入学年份',value:'2018'}
    assert_includes fields,{label:'毕业年份',value:'2022'}
    assert_includes fields,{label:'行业',value:'教育'}
    command(a,@alice,'save',original.merge(published:false))
    assert_empty state(a,@bob)[:cards]
    assert_raises(a::Error) { command(a,@alice,'save',original.merge(admission_year:'2018oops')) }
    command(a,@alice,'save',map_data)
    command(a,@alice,'save',map_data.merge(latitude:'',longitude:'',bio:'只修改介绍'))
    assert_equal '30.75',profile.reload.latitude.to_s('F')
    SiteSetting.alumni_map_server_key=''
    command(a,@alice,'save',map_data.merge(city:'北京',latitude:'',longitude:''))
    assert_nil profile.reload.latitude
    assert_raises(a::Error) { command(a,@alice,'save',map_data.merge(longitude:'')) }
  end
  def test_map_location_catalog_and_clear_location
    a=DiscourseAlumniMap
    assert_equal 111,a::Locations.options(nil).size
    assert_empty a::Locations.options('../../etc/passwd')
    assert a::Locations.options('CN').any? { |s| s['name']=='四川' }
    assert a::Locations.options('CN','510000').any? { |s| s['name']=='成都' }
    command(a,@alice,'save',map_data.merge(province:'四川',latitude:'',longitude:''))
    p=a::Profile.find_by!(user_id:@alice.id)
    assert_in_delta 30.5,p.latitude,0.001
    command(a,@alice,'save',map_data.merge(country:'美国',province:'California',city:'San Francisco',latitude:'',longitude:''))
    assert_in_delta 37.75,p.reload.latitude,0.001
    assert_in_delta(-122.5,p.longitude,0.001)
    command(a,@alice,'save',map_data.merge(country:'',province:'',city:'',latitude:'',longitude:'',location_changed:true))
    assert_nil p.reload.country
    assert_nil p.latitude
  end
  def test_map_failed_geocoder_does_not_block_withdrawing_publication
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data)
    SiteSetting.alumni_map_server_key='synthetic-nonsecret-test-key'
    original=a::Service.method(:geocode)
    a::Service.define_singleton_method(:geocode) { |*args| raise a::Error,'Unavailable' }
    command(a,@alice,'save',map_data.merge(city:'未收录城市',latitude:'',longitude:'',published:false))
    assert_nil a::Profile.first.latitude
    refute a::Profile.first.published
    assert_equal '未收录城市',a::Profile.first.city
  ensure
    a::Service.define_singleton_method(:geocode,original) if original
    SiteSetting.alumni_map_server_key=''
  end
  def test_map_public_listing_has_no_silent_limit_and_admin_can_find_all_cards
    a=DiscourseAlumniMap
    505.times { |i| a::Profile.create!(user_id:100000+i,nickname:"校友#{i}",published:true,country:'中国',province:'四川',city:'成都') }
    result=state(a)
    assert_equal 505,result[:cards].size
    assert_equal 505,result[:map][:regions][:province].sum { |r| r[:count] }
    admin=state(a,@admin,view:'admin',page:11)
    assert_equal 5,admin[:cards].size
    assert_equal 11,admin[:pagination][:pages]
    assert_equal 1,state(a,@admin,view:'admin',q:'校友504')[:cards].size
    assert_equal '没有找到匹配的校友',state(a,@alice,q:'不存在')[:empty_title]
  end
  def test_map_username_privacy_and_owner_export
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data.merge(show_username:true))
    assert_equal "/u/#{@alice.username}",state(a,@bob)[:cards].first[:profile_url]
    command(a,@alice,'save',map_data.merge(show_username:false))
    assert_nil state(a,@bob)[:cards].first[:profile_url]
    a::Legacy.create!(source:'User',legacy_id:'old-alice',data:{externalUserId:@alice.id.to_s,email:'private@example.test'})
    a::Legacy.create!(source:'AlumniProfile',legacy_id:'old-card',data:{userId:'old-alice',bio:'private'})
    assert_equal 1,a::UserLifecycle.archive(@alice.id)[:profiles].size
    assert_empty a::UserLifecycle.archive(@bob.id)[:profiles]
  end
  def test_map_account_events_purge_archived_identity_even_when_disabled
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data)
    p=a::Profile.first
    a::Legacy.create!(source:'User',legacy_id:'old-alice',data:{externalUserId:@alice.id.to_s,email:'private@example.test'})
    a::Legacy.create!(source:'AlumniProfile',legacy_id:'old-card',target_kind:'Profile',target_id:p.id,data:{userId:'old-alice',bio:'private'})
    command(a,@admin,'moderate',{id:p.id,status:'hidden',reason:'private reason'})
    a::Shared.deliver
    SiteSetting.alumni_map_enabled=false
    UserAnonymizer.make_anonymous(@alice,@admin)
    assert_empty a::Profile.where(user_id:@alice.id)
    assert_empty a::Legacy.where(source:['User','AlumniProfile'])
    assert_empty a::Audit.where(target_kind:'Profile',target_id:p.id)
    assert_empty a::Event.where(user_id:@alice.id)
    assert_empty a::Command.where(user_id:@alice.id)
    SiteSetting.alumni_map_enabled=true
    command(a,@bob,'save',map_data)
    @bob.destroy!
    assert_empty a::Profile.where(user_id:@bob.id)
  end
  def test_map_real_user_merge_transfers_private_card_and_preserves_target_on_conflict
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data.merge(show_username:true))
    UserMerger.new(@alice,@bob,@admin).merge!
    transferred=a::Profile.find_by!(user_id:@bob.id)
    refute transferred.published
    refute transferred.show_username
    assert_empty a::Profile.where(user_id:@alice.id)
    command(a,@carol,'save',map_data.merge(nickname:'来源名片'))
    UserMerger.new(@carol,@bob,@admin).merge!
    assert_equal 1,a::Profile.count
    assert_equal transferred.id,a::Profile.first.id
  end
  def test_map_readonly_snapshot_cannot_be_edited_even_by_admin
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data)
    SiteSetting.alumni_map_read_only=true
    before=[a::Profile.first.attributes,a::Command.count,a::Event.count]
    assert_raises(a::Error) { command(a,@alice,'save',map_data.merge(bio:'不应保存')) }
    assert_raises(a::Error) { command(a,@admin,'moderate',{id:a::Profile.first.id,status:'hidden',reason:'不应保存'}) }
    assert_empty state(a,@alice,{view:'me'})[:forms]
    assert state(a,@alice)[:read_only]
    assert_equal before,[a::Profile.first.attributes,a::Command.count,a::Event.count]
  end
  def test_map_regions_partition_public_profiles_and_keep_unlocated_members
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data.merge(province:'四川'))
    command(a,@bob,'save',map_data.merge(nickname:'第二位',province:'四川',city:'绵阳',latitude:'31.5',longitude:'104.75'))
    command(a,@carol,'save',map_data.merge(nickname:'无坐标',province:'四川',city:'未收录城市',latitude:'',longitude:''))
    result=state(a,@alice)
    province=result[:map][:regions][:province].first
    assert_equal 3,province[:count]
    assert_equal 3,result[:map][:regions][:city].size
    assert_equal result[:cards].map { |c| c[:id].to_i }.sort,province[:ids].sort
    assert_in_delta 31.125,province[:lat],0.001
    command(a,@carol,'save',map_data.merge(published:false))
    assert_equal 2,state(a,@alice)[:map][:regions][:province].sum { |region| region[:count] }
    command(a,@admin,'moderate',{id:a::Profile.find_by!(user_id:@bob.id).id,status:'hidden',reason:'测试'})
    assert_equal 1,state(a,@alice)[:map][:regions][:province].sum { |region| region[:count] }
  end
  def test_map_import_dry_run_apply_and_checksum
    a=DiscourseAlumniMap
    payload={format:'riverside-community-v1',project:'alumni-map',tables:{User:[{id:'u1',externalUserId:@alice.id.to_s}],AlumniProfile:[{id:'p1',userId:'u1',nickname:'旧名片',isPublished:true,showForumUsername:false,latitude:30.678,longitude:104.123,country:'中国',city:'成都',address:'旧详细地址'}]}}.deep_stringify_keys
    result=a::Importer.new(payload).run(sha:'abc')
    assert_equal 0,a::Profile.count;assert_equal 1,result[:counts]['river_alumni_map_profiles']
    assert_raises(a::Error) { a::Importer.new(payload).run(sha:'abc',apply:true,expected_sha:'wrong') }
    SiteSetting.alumni_map_enabled=false
    a::Importer.new(payload).run(sha:'abc',apply:true,expected_sha:'abc')
    assert_equal 1,a::Profile.count
    assert_equal '30.75',a::Profile.first.latitude.to_s('F')
    refute a::Profile.first.details.key?('address')
    assert a::Importer.new(payload).run(sha:'abc',apply:true,expected_sha:'abc')[:already_imported]
  end
  def test_map_new_endpoints_require_membership_and_export_only_current_owner
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data)
    command(a,@bob,'save',map_data.merge(nickname:'other private',published:false))
    guest,headers=http(@stranger)
    ['/alumni-map/locations.json','/alumni-map/export'].each do |path|
      guest.get(path,headers:headers)
      assert_equal 403,guest.response.status
    end
    owner,headers=http(@alice)
    owner.get('/alumni-map/export',params:{user_id:@bob.id},headers:headers)
    assert_equal 200,owner.response.status
    assert_equal @alice.id,JSON.parse(owner.response.body).dig('profile','user_id')
    refute_includes owner.response.body,'other private'
    assert_includes owner.response.headers['Cache-Control'],'no-store'
    owner.get('/alumni-map/locations.json',params:{country:'CN',province:'510000'},headers:headers)
    assert_equal 200,owner.response.status
    assert JSON.parse(owner.response.body).any? { |c| c['name']=='成都' }
  end
  def test_map_frame_has_scoped_csp_and_requires_membership
    session,headers=http(@alice)
    session.get('/alumni-map/map-frame',headers:headers)
    assert_equal 200,session.response.status
    policy=session.response.headers.fetch('Content-Security-Policy')
    assert_includes policy,"sandbox allow-scripts"
    refute_includes policy,'allow-same-origin'
    assert_includes policy,"'unsafe-eval'"
    assert_includes session.response.headers['Cache-Control'],'no-store'
    session.get('/alumni-map',headers:headers)
    refute_includes session.response.headers.fetch('Content-Security-Policy'),"'unsafe-eval'"
    stranger,stranger_headers=http(@stranger)
    stranger.get('/alumni-map/map-frame',headers:stranger_headers)
    assert_equal 403,stranger.response.status
  end
end

class AlumniMapTest
  def test_lazy_cards_are_paginated_and_recheck_publication
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data.merge(show_username:true))
    command(a,@bob,'save',map_data.merge(nickname:'仍然匿名'))
    command(a,@carol,'save',map_data.merge(nickname:'私密名片',published:false))
    lazy=state(a,@alice,{lazy_cards:'1'})
    assert_empty lazy[:cards]
    assert_equal 2,lazy[:map][:profile_count]
    region=lazy[:map][:regions][:province].first
    cards=state(a,@alice,{cards_only:'1',region_key:region[:key]})
    assert_equal 2,cards[:pagination][:total]
    assert_equal @alice.username,cards[:cards].find { |c| c[:forum_user] }[:forum_user][:username]
    refute_includes cards.to_json,@bob.username
    refute_includes cards.to_json,'私密名片'
    command(a,@alice,'save',map_data.merge(published:false))
    assert_equal 1,state(a,@bob,{cards_only:'1',region_key:region[:key]})[:pagination][:total]
    assert_empty state(a,@bob,{cards_only:'1',region_key:'forged'})[:cards]
    assert_raises(Discourse::InvalidAccess) { state(a,@stranger,{cards_only:'1',region_key:region[:key]}) }
  end
  def test_prepared_coordinates_cannot_overwrite_a_concurrent_edit
    a=DiscourseAlumniMap
    command(a,@alice,'save',map_data)
    prepared=a::Service.prepare_location(@alice,map_data.deep_stringify_keys)
    command(a,@alice,'save',map_data.merge(bio:'另一个窗口的编辑'))
    assert_raises(a::Error) do
      a::Shared.command(@alice,'save',map_data.deep_stringify_keys,SecureRandom.uuid) { a::Service.call(@alice,'save',map_data.deep_stringify_keys,prepared:prepared) }
    end
  end
end
