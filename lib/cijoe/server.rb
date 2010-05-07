require 'sinatra/base'
require 'erb'

class CIJoe
  class Server < Sinatra::Base
    attr_reader :joes

    dir = File.dirname(File.expand_path(__FILE__))

    set :views,  "#{dir}/views"
    set :public, "#{dir}/public"
    set :static, true
    set :lock, true

    before { joes.each { |k, v| v.restore } }

    get '/' do
      erb(:index)
    end

    get '/:project/ping' do
      if joes[params[:project]].building? || !joes[params[:project]].last_build || !joes[params[:project]].last_build.worked?
        halt 412, joes[params[:project]].last_build ? joes[params[:project]].last_build.sha : "building"
      end

      joes[params[:project]].last_build.sha
    end

    get '/:project/?' do
      erb(:template, {}, :joe => joes[params[:project]])
    end

    post '/:project/?' do
      payload = params[:payload].to_s
      if payload.empty? || payload.include?(joes[params[:project]].git_branch)
        joes[params[:project]].build
      end
      redirect request.path
    end


    helpers do
      include Rack::Utils
      alias_method :h, :escape_html

      # thanks integrity!
      def ansi_color_codes(string)
        string.gsub("\e[0m", '</span>').
          gsub(/\e\[(\d+)m/, "<span class=\"color\\1\">")
      end

      def pretty_time(time)
        time.strftime("%Y-%m-%d %H:%M")
      end

      def cijoe_root
        root = request.path
        root = "" if root == "/" + (params[:project] || '')
        root
      end
    end

    def initialize(*args)
      super
      check_project
      @joes = {}
      options.project_path.each {|k,v|
        @joes[k] = CIJoe.new(v)
      }

      CIJoe::Campfire.activate
    end

    def self.start(host, port, project_path)
      set :project_path, project_path
      CIJoe::Server.run! :host => host, :port => port
    end

    def self.project_path=(project_path)
      # FIXME: get him back
      # user, pass = Config.cijoe(project_path).user.to_s, Config.cijoe(project_path).pass.to_s
      # if user != '' && pass != ''
      #   use Rack::Auth::Basic do |username, password|
      #     [ username, password ] == [ user, pass ]
      #   end
      #   puts "Using HTTP basic auth"
      # end
      set :project_path, Proc.new{project_path}
    end

    def check_project
      options.project_path.each do |k,path|
        if path.nil? || !File.exists?(File.expand_path(path))
          puts "Whoops! I need the path to a Git repo."
          puts "  $ git clone git@github.com:username/project.git project"
          abort "  $ cijoe project"
        end
      end
    end
  end
end
