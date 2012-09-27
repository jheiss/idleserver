class DashboardController < ApplicationController
  def index
    @idleness_data_url = url_for(:action => 'chart', :chart => 'idleness', :format => :json)
    @client_data_url = url_for(:action => 'chart', :chart => 'client', :format => :json)
    @total_count = Client.count
  end
  
  def chart
    respond_to do |format|
      format.json do
        data = []
        case params[:chart]
        when 'client'
          client_counts = []
          oldest = Client.order('created_at').first
          if oldest
            logger.debug oldest
            startmonth = Date.new(oldest.created_at.year, oldest.created_at.month, 1)
            now = Time.now
            endmonth = Date.new(now.year, now.month, 1)
            (startmonth..endmonth).select {|d| d.day == 1}.each do |month|
              client_count = Client.where('created_at <= ?', month).count
              # JSON timestamps are millis since epoch
              client_counts << [month.to_time.to_i * 1000, client_count]
            end
            # Throw in an entry for right now so the graph has current data
            client_counts << [now.to_i * 1000, Client.count]
          end
          data = [{:label => "# of Clients", :data => client_counts}]
        when 'idleness'
          idleness_counts = []
          10.step(100, 10).each do |percent|
            # 0%-100% is 101 steps so we need a special case to have the first
            # range in the graph be 0-10.  Remaining ranges will be 11-20,
            # 21-30, etc.
            count = nil
            if percent == 10
              count = Client.count(:conditions => ["idleness >= ? AND idleness <= ?", percent-10, percent])
            else
              count = Client.count(:conditions => ["idleness > ? AND idleness <= ?", percent-10, percent])
            end
            # data << { :label => "#{percent}%", :data => count }
            idleness_counts << [percent, count]
          end
          data = [{:label => "% Idleness", :data => idleness_counts}]
        end
        render :json => data
      end
    end
  end
end
