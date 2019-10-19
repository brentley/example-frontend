require 'net/http'
require 'resolv'
require 'uri'

class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  # Example endpoint that calls the backend nodejs api
  def index
    begin
      # req = Net::HTTP::Get.new(nodejs_uri.path.presence || "/")
      req = Net::HTTP::Get.new(nodejs_uri.request_uri)
      if request.headers["HTTP_CANARY_FLEET"].present?
        req["canary_fleet"] = request.headers["HTTP_CANARY_FLEET"]
      end

      res = Net::HTTP.start(nodejs_uri.host, nodejs_uri.port) {|http|
        http.read_timeout = 2
        http.open_timeout = 2
        http.request(req)
      }

      if res.code == '200'
        @text = res.body
      else
        @text = "no backend found"
      end

    rescue => e
      logger.error e.message
      logger.error e.backtrace.join("\n")
      @text = "no backend found"
    end

    begin
      # crystalreq = Net::HTTP::Get.new(crystal_uri.path.presence || "/")
      crystalreq = Net::HTTP::Get.new(crystal_uri.request_uri)
      if request.headers["HTTP_CANARY_FLEET"].present?
        crystalreq["canary_fleet"] = request.headers["HTTP_CANARY_FLEET"]
      end

      crystalres = Net::HTTP.start(crystal_uri.host, crystal_uri.port) {|http|
        http.read_timeout = 2
        http.open_timeout = 2
        http.request(crystalreq)
      }

      if crystalres.code == '200'
        @crystal = crystalres.body
      else
        @crystal = "no backend found"
      end

    rescue => e
      logger.error e.message
      logger.error e.backtrace.join("\n")
      @crystal = "no backend found"
    end

    if params[:type].present? && params[:type] == "json"
      response = { }
      response[:ruby] = {
        :az   => @az,
        :hash => @code_hash,
        :canary_fleet => request.headers["HTTP_CANARY_FLEET"].present?
      }

      if @crystal != "no backend found"
        response[:crystal] = { :text => @crystal }
      end

      if @text != "no backend found"
        response[:nodejs] = { :text => @text }
      end

      render json: response.to_json
      
    end

  end

  def json
    redirect_to root_path(:type => "json")
  end

  # This endpoint is used for health checks. It should return a 200 OK when the app is up and ready to serve requests.
  def health
    render plain: "OK"
  end

  def crystal_uri
    if ENV['MESH_RUN'].present? && ENV['MESH_RUN'] == 'true' 
      uri = URI(ENV["CRYSTAL_URL"])  
    else
      expand_url ENV["CRYSTAL_URL"]
    end
  end

  def nodejs_uri
    if ENV['MESH_RUN'].present? && ENV['MESH_RUN'] == 'true' 
      uri = URI(ENV["NODEJS_URL"])
    else
      expand_url ENV["NODEJS_URL"]
    end
  end

  # Resolve the SRV records for the hostname in the URL
  def expand_url(url)
    uri = URI(url)
    resolver = Resolv::DNS.new()

    # if host is relative, append the service discovery name
    host = uri.host.count('.') > 0 ? uri.host : "#{uri.host}.#{ENV["_SERVICE_DISCOVERY_NAME"]}"

    # lookup the SRV record and use if found
    begin
      srv = resolver.getresource(host, Resolv::DNS::Resource::IN::SRV)
      uri.host = srv.target.to_s
      uri.port = srv.port.to_s
      logger.info "uri port is #{uri.port}"
      if uri.port == 0
        uri.port = 80
        logger.info "uri port is now #{uri.port}"
      end
    rescue => e
      logger.error e.message
      logger.error e.backtrace.join("\n")
    end

    logger.info "expanded #{url} to #{uri}"
    uri
  end

  before_action :discover_availability_zone
  before_action :code_hash

  def discover_availability_zone
    @az = ENV["AZ"]
  end

  def code_hash
    @code_hash = ENV["CODE_HASH"]
  end

  def custom_header
    response.headers['Cache-Control'] = 'max-age=86400, public'
  end
  
end