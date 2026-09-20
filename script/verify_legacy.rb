# frozen_string_literal: true
# Read-only verification immediately after initial import, before accepting edits.
raw=File.binread(ARGV.fetch(0))
payload=JSON.parse(raw)
raise 'Wrong export format' unless payload['format']=='riverside-community-v1' && payload['project']=='alumni-map'
a=DiscourseAlumniMap
field_map={'admission_year'=>'admissionYear','graduation_year'=>'graduationYear','school'=>'school','major'=>'major','company'=>'company','role_title'=>'roleTitle','industry'=>'industry','free_time'=>'freeTime','bio'=>'bio','contact_note'=>'contactNote'}
report=nil
ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY')
  owners=payload.fetch('tables').fetch('User').index_by { |u| u.fetch('id') }
  profiles=payload['tables'].fetch('AlumniProfile')
  raise 'Profile count mismatch' unless a::Profile.count==profiles.size
  profiles.each do |old|
    legacy=a::Legacy.find_by!(source:'AlumniProfile',legacy_id:old.fetch('id'))
    profile=a::Profile.find(legacy.target_id)
    owner=owners.fetch(old.fetch('userId'))
    expected={user_id:Integer(owner.fetch('externalUserId'),10),nickname:old['nickname'],published:!!old['isPublished'],show_username:!!old['showForumUsername'],status:old['hiddenAt'] ? 'hidden' : 'visible',hidden_reason:old['hiddenReason'],country:old['country'],province:old['province'],city:old['city'],details:field_map.to_h { |new_key,old_key| [new_key,old[old_key]] }}
    raise 'Owner no longer exists' unless User.exists?(expected[:user_id])
    expected.each { |key,value| raise "Profile field mismatch: #{key}" unless profile.public_send(key)==value }
    %w[latitude longitude].each { |key| expected_coord=old[key] && (old[key].to_f*4).round/4.0; raise 'Coordinate mismatch' unless profile.public_send(key)&.to_f==expected_coord }
    %w[createdAt updatedAt].each { |key| actual=profile.public_send(key=='createdAt' ? :created_at : :updated_at);raise 'Timestamp mismatch' unless (actual-Time.iso8601(old[key])).abs<0.001 }
    raise 'Profile archive mismatch' unless legacy.data==old
  end
  owners.each_value { |old| raise 'User archive mismatch' unless a::Legacy.find_by!(source:'User',legacy_id:old.fetch('id')).data==old }
  report={verified:true,sha256:Digest::SHA256.hexdigest(raw),users:owners.size,profiles:profiles.size,published:a::Profile.where(published:true,status:'visible').count,located_public:a::Profile.where(published:true,status:'visible').where.not(latitude:nil,longitude:nil).count,commands:a::Command.count,events:a::Event.count}
end
puts JSON.pretty_generate(report)
