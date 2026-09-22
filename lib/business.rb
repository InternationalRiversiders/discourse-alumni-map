# frozen_string_literal: true
require 'net/http'
module DiscourseAlumniMap
  class Profile < Record
    self.table_name = 'river_alumni_map_profiles'
  end
  module Service
    DETAILS = { 'admission_year'=>'入学年份','graduation_year'=>'毕业年份','school'=>'学院','major'=>'专业','company'=>'公司 / 机构','role_title'=>'职位 / 方向','industry'=>'行业','free_time'=>'空闲时间','bio'=>'自我介绍','contact_note'=>'联系偏好' }.freeze
    def self.profile_form(item, user)
      fields = [Ui.field('nickname','昵称',item&.nickname || user.username,required:true),Ui.field('country','国家',item&.country || '中国'),Ui.field('province','省 / 州',item&.province),Ui.field('city','城市',item&.city),Ui.field('latitude','城市纬度（选填）',item&.latitude,type:'number'),Ui.field('longitude','城市经度（选填）',item&.longitude,type:'number')]
      fields += DETAILS.map { |key,label| Ui.field(key,label,item&.details&.[](key),type: %w[bio contact_note].include?(key) ? 'textarea' : 'text') }
      fields += [Ui.field('published','向校友公开资料',item&.published,type:'checkbox'),Ui.field('show_username','展示论坛用户名',item&.show_username,type:'checkbox')]
      fields.each { |field| field[:maxlength] = field[:name]=='nickname' ? 40 : field[:name]=='bio' ? 600 : %w[admission_year graduation_year].include?(field[:name]) ? 4 : 160 }
      Ui.form('我的校友名片','save',fields,button:'保存名片')
    end
    def self.state(user, query)
      Access.check!(user)
      tabs=[['map','校友地图'],['me','我的名片']];tabs << ['admin','管理'] if Access.admin?(user)
      out=Ui.shell(user,query,tabs,empty_title:'这里还没有公开的校友名片',empty_text:'先完善自己的资料，再选择是否公开。')
      if out[:view]=='me'
        p=Profile.find_by(user_id:user.id)
        out[:forms]=[profile_form(p,user)]
        out[:note]=p&.status=='hidden' ? "你的名片已被管理员隐藏：#{p.hidden_reason}。编辑不会自动恢复公开。" : '只保存城市级坐标；未勾选公开时，仅本人可见。'
      elsif out[:view]=='admin'
        Access.check!(user,admin:true)
        q=query['q'].to_s.strip
        scope=Profile.all
        scope=scope.where('nickname ILIKE :q OR city ILIKE :q OR country ILIKE :q OR province ILIKE :q OR user_id IN (SELECT id FROM users WHERE username ILIKE :q)', q:"%#{ActiveRecord::Base.sanitize_sql_like(q)}%") if q.present?
        pages=[(scope.count/50.0).ceil,1].max
        page=[[query['page'].to_i,1].max,pages].min
        profiles=scope.order(updated_at: :desc,id: :desc).offset((page-1)*50).limit(50).to_a
        usernames=User.where(id:profiles.map(&:user_id)).index_by(&:id)
        out[:filters]=[{name:'q',label:'查找名片或论坛账号',value:q,placeholder:'昵称、用户名或地区'}]
        out[:pagination]={page:page,pages:pages,previous:page>1 ? {view:'admin',q:q,page:page-1} : nil,next:page<pages ? {view:'admin',q:q,page:page+1} : nil}
        out[:cards]=profiles.map do |p|
          account=usernames[p.user_id];username=account&.username
          publication=p.status=='hidden' ? '已隐藏' : p.published ? '已公开' : '未公开'
          Ui.card(p.id,p.nickname,[p.country,p.province,p.city,p.details['company'],p.hidden_reason.presence && "处理原因：#{p.hidden_reason}"].reject(&:blank?).join(' · '),
            tag:publication,subtitle:username,forum_user:account && Shared.forum_user(account),profile_url:username && "/u/#{ERB::Util.url_encode(username)}",
            forms:[Ui.form('管理名片','moderate',[Ui.field('status','处理方式',p.status=='hidden' ? 'visible' : 'hidden',type:'select',options:[['hidden','隐藏'],['visible','解除隐藏（由本人重新公开）']]),Ui.field('reason','理由',nil,required:true)],{'id'=>p.id},button:'确认')])
        end
        out[:note]="共 #{scope.count} 张名片。解除隐藏不会代替本人公开资料。"
      else
        scope=Profile.where(published:true,status:'visible')
        q=query['q'].to_s.strip
        scope=scope.where('nickname ILIKE :q OR city ILIKE :q OR country ILIKE :q OR province ILIKE :q',q:"%#{ActiveRecord::Base.sanitize_sql_like(q)}%") if q.present?
        profiles=scope.order(updated_at: :desc,id: :desc).to_a
        usernames=User.where(id:profiles.select(&:show_username).map(&:user_id)).index_by(&:id)
        out[:filters]=[{name:'q',label:'寻找校友',value:q,placeholder:'昵称、国家或城市'}]
        out[:stats]=[{label:'公开名片',value:profiles.size},{label:'国内省份',value:profiles.select { |p| p.country=='中国' }.map(&:province).reject(&:blank?).uniq.size},{label:'国家 / 地区',value:profiles.map(&:country).reject(&:blank?).uniq.size}]
        out[:map]={key:SiteSetting.alumni_map_amap_key,security:SiteSetting.alumni_map_amap_security_code,points:profiles.filter_map { |p| {id:p.id,lat:p.latitude.to_f,lng:p.longitude.to_f,title:p.nickname,city:p.city} if p.latitude && p.longitude },regions:{province:regions(profiles,'province'),city:regions(profiles,'city')}}
        out[:cards]=profiles.map do |p|
          d=p.details
          account=p.show_username ? usernames[p.user_id] : nil;username=account&.username
          Ui.card(p.id,p.nickname,d['bio'],tag:[p.country,p.province,p.city].reject(&:blank?).uniq.join(' · '),subtitle:username,forum_user:account && Shared.forum_user(account),profile_url:username && "/u/#{ERB::Util.url_encode(username)}",profile_fields:DETAILS.filter_map { |key,label| {label:label,value:d[key]} if key!='bio' && d[key].present? })
        end
        out[:note]='仅显示城市级位置。点击地区查看校友；未填写坐标的名片也可通过地区选择查看。'
        if q.present? && profiles.empty?
          out[:empty_title]='没有找到匹配的校友'
          out[:empty_text]='可以换一个昵称或地区，或清空搜索条件。'
        end
      end
      if SiteSetting.alumni_map_read_only
        out[:read_only]=true
        out[:forms]=[]
        out[:cards].each { |card| card.delete(:forms);card.delete(:actions) }
        out[:note]='这是旧站数据的只读快照。编辑、公开设置及管理操作请在演示站测试。'
      end
      out
    end
    STATE_COUNTRIES = %w[中国 美国 加拿大 澳大利亚 俄罗斯 巴西 印度 阿根廷 墨西哥 印度尼西亚].freeze
    def self.regions(profiles,level)
      profiles.group_by do |p|
        country=p.country.presence || '未填写国家'
        if country=='中国'
          [country,p.province.to_s,level=='city' ? p.city.to_s : nil]
        elsif STATE_COUNTRIES.include?(country) && p.province.present?
          [country,p.province]
        else
          [country]
        end
      end.map do |parts,people|
        located=people.select { |p| p.latitude && p.longitude }
        {key:Digest::SHA256.hexdigest([level,parts].to_json)[0,20],label:parts.reject(&:blank?).uniq.join(' · '),count:people.size,ids:people.map(&:id),lat:located.empty? ? nil : located.sum { |p| p.latitude.to_f }/located.size,lng:located.empty? ? nil : located.sum { |p| p.longitude.to_f }/located.size}
      end.sort_by { |region| [-region[:count],region[:label]] }
    end
    def self.call(user,operation,data)
      Access.check!(user)
      raise Error,'这是只读快照，请到演示站测试编辑' if SiteSetting.alumni_map_read_only
      case operation
      when 'save'
        p=Profile.find_or_initialize_by(user_id:user.id)
        details=DETAILS.keys.to_h { |k| [k,Shared.text(data[k],k=='bio' ? 600 : 160,required:false)] }
        %w[admission_year graduation_year].each do |key|
          value=details[key]
          raise Error,'年份应为 1950 至 2100 之间的四位数字' if value.present? && (!value.match?(/\A\d{4}\z/) || !value.to_i.between?(1950,2100))
        end
        location=resolve_location(p,data)
        p.update!(**location,nickname:Shared.text(data['nickname'],40),published:p.status!='hidden' && Shared.bool(data['published']),show_username:Shared.bool(data['show_username']),details:details)
        {message:p.city.present? && p.latitude.nil? ? '名片已保存。城市坐标暂未找到，仍可通过地区选择查看名片。' : '名片已保存，位置仅精确到城市级别'}
      when 'moderate'
        Access.check!(user,admin:true);p=Profile.find(data['id']);status=data['status']
        raise Error,'无效状态' unless %w[hidden visible].include?(status)
        Shared.audit(user,'profile_'+status,p,data['reason'])
        p.update!(status:status,published:false,hidden_reason:status=='hidden' ? Shared.text(data['reason'],500) : nil)
        Shared.notify(p.user_id,status=='hidden' ? '你的校友名片已被隐藏，请查看处理原因' : '你的校友名片已解除隐藏，可在我的名片中重新选择公开', '/alumni-map?view=me',key:"profile:#{p.id}:#{p.updated_at.to_f}")
        {}
      else raise Error,'未知操作'
      end
    end
    def self.resolve_location(profile,data)
      country=Shared.text(data['country'],80,required:false)
      province=Shared.text(data['province'],80,required:false)
      city=Shared.text(data['city'],80,required:false)
      # Legacy profiles may have no city or coordinates. Editing their biography
      # or withdrawing publication must never depend on a geocoding service.
      if country.blank? || city.blank?
        return {country:country.presence,province:province.presence,city:city.presence,latitude:nil,longitude:nil} if Shared.bool(data['location_changed'])
        return {}
      end
      location={country:country,province:province,city:city}
      latitude=data['latitude'].presence;longitude=data['longitude'].presence
      raise Error,'经纬度请同时填写或同时留空' if latitude.nil? != longitude.nil?
      if latitude.nil?
        unchanged=[profile.country,profile.province.to_s,profile.city]==[country,province,city]
        return location if unchanged
        coordinates=Locations.coordinates(country,province,city)
        if !coordinates && country=='中国' && SiteSetting.alumni_map_server_key.present?
          begin
            coordinates=geocode(country,province,city)
          rescue Error
            # A provider outage must not block saving or withdrawing a profile.
            coordinates=nil
          end
        end
        return location.merge(latitude:nil,longitude:nil) unless coordinates
        latitude,longitude=coordinates
      end
      lat=Float(latitude,exception:false);lng=Float(longitude,exception:false)
      raise Error,'城市坐标无效' unless lat && lng && lat.finite? && lng.finite? && lat.between?(-90,90) && lng.between?(-180,180)
      location.merge(latitude:(lat*4).round/4.0,longitude:(lng*4).round/4.0)
    end
    def self.geocode(country,province,city)
      raise Error,'请填写城市坐标，或由管理员配置高德地理编码服务' if country!='中国' || SiteSetting.alumni_map_server_key.blank?
      key="alumni-map-geocode:#{Digest::SHA256.hexdigest([province,city].join(':'))}"
      Discourse.cache.fetch(key,expires_in:1.day) do
        uri=URI('https://restapi.amap.com/v3/geocode/geo');uri.query=URI.encode_www_form(key:SiteSetting.alumni_map_server_key,address:city,city:province)
        response=Net::HTTP.start(uri.host,443,use_ssl:true,open_timeout:5,read_timeout:10) { |http| http.get(uri.request_uri) }
        raise Error,'城市查询失败，请稍后再试' unless response.code=='200' && response.body.bytesize<1.megabyte
        payload=JSON.parse(response.body);location=payload.dig('geocodes',0,'location')
        raise Error,'没有找到城市，请填写城市坐标' unless payload['status']=='1' && location.is_a?(String)
        longitude,latitude=location.split(',');[latitude,longitude]
      end
    rescue Net::OpenTimeout,Net::ReadTimeout,JSON::ParserError,SocketError,IOError,SystemCallError,OpenSSL::SSL::SSLError
      raise Error,'城市查询暂时不可用'
    end
    def self.media_allowed?(user,item) = false
  end
end
