require 'magickly'
require 'image_size'
require 'face'

Magickly.dragonfly.configure do |c|
  c.log_commands = true
  
  c.analyser.add :face_data do |temp_object|
    Mustachio.face_client.faces_detect(:file => temp_object.file, :attributes => 'none')['photos'].first
  end
  
  c.analyser.add :face_data_as_px do |temp_object|
    data = Mustachio.face_client.faces_detect(:file => temp_object.file, :attributes => 'none')['photos'].first # TODO use #face_data
    
    data['tags'].map! do |face|
      Mustachio::FACE_POS_ATTRS.each do |pos_attr|
        if face[pos_attr].nil?
          puts "WARN: missing position attribute '#{pos_attr}'"
        else
          face[pos_attr]['x'] *= (data['width'] / 100.0)
          face[pos_attr]['y'] *= (data['height'] / 100.0)
        end
      end
      
      face
    end
    
    data
  end
  
  c.job :mustachify do |stache_num_param|
    photo_data = @job.face_data_as_px
    width = photo_data['width']
    
    commands = ['-virtual-pixel transparent']
    photo_data['tags'].each do |face|
      stache_num = case stache_num_param
        when true
          0
        when 'true'
          0
        when 'rand'
          rand(Mustachio.mustaches.size)
        else
          stache_num_param.to_i
      end
      
      mustache = Mustachio.mustaches[stache_num]
      
      # perform transform such that the mustache is the height
      # of the upper lip, and the bottom-center of the stache
      # is mapped to the center of the mouth
      rotation = Math.atan(
        ( face['mouth_right']['y'] - face['mouth_left']['y'] ).to_f /
        ( face['mouth_right']['x'] - face['mouth_left']['x'] ).to_f
      ) / Math::PI * 180.0
      desired_height = Math.sqrt(
        ( face['nose']['x'] - face['mouth_center']['x'] ).to_f**2 +
        ( face['nose']['y'] - face['mouth_center']['y'] ).to_f**2
      )
      mouth_intersect = mustache['height'] - mustache['mouth_overlap']
      scale = desired_height / mouth_intersect
      
      srt_params = [
        [ mustache['width'] / 2.0, mouth_intersect - mustache['vert_offset'] ].map{|e| e.to_i }.join(','), # bottom-center of stache
        scale, # scale
        rotation, # rotate
        [ face['mouth_center']['x'], face['mouth_center']['y'] ].map{|e| e.to_i }.join(',') # middle of mouth
      ]
      srt_params_str = srt_params.join(' ')
      
      commands << "\\( #{mustache['file_path']} +distort SRT '#{srt_params_str}' \\)"
    end
    commands << "-flatten"
    
    command_str = commands.join(' ')
    process :convert, command_str
  end
end

module Mustachio
  FACE_POS_ATTRS = ['center', 'eye_left', 'eye_right', 'mouth_left', 'mouth_center', 'mouth_right', 'nose']
  
  class << self
    def face_client
      @@face_client
    end
    
    def mustaches
      @@mustaches
    end
    
    def setup
      @@face_client = Face.get_client(
        :api_key => (ENV['MUSTACHIO_FACE_API_KEY'] || raise("Please set MUSTACHIO_FACE_API_KEY.")),
        :api_secret => (ENV['MUSTACHIO_FACE_API_SECRET'] || raise("Please set MUSTACHIO_FACE_API_SECRET."))
      )
      
      staches = YAML.load(File.read(File.join(File.dirname(__FILE__), '..', 'config', 'staches.yml')))
      staches.map! do |stache|
        stache['vert_offset'] ||= 0
        stache['mouth_overlap'] ||= 0
        
        stache['file_path'] = File.expand_path(File.join(File.dirname(__FILE__), '..', 'public', 'images', 'staches', stache['filename']))
        unless stache['width'] && stache['height']
          stache['width'], stache['height'] = ImageSize.new(File.new(stache['file_path'])).get_size
        end
        stache
      end
      @@mustaches = staches
    end
  end
  
  
  self.setup
end
