class DashboardController < ApplicationController
  def set_counts
    @total_count    = Client.count
  end
  def set_charts
    @client_chart = open_flash_chart_object(500, 300, url_for( :action => 'chart', :chart => 'client', :format => :json ))
    @idleness_chart = open_flash_chart_object(500, 300, url_for( :action => 'chart', :chart => 'idleness', :format => :json ))
  end
  
  def index
    set_counts
    set_charts
  end
  
  def chart
    respond_to do |format|
      format.html {
        set_charts
        case params[:chart]
        when 'client'
          render :partial => 'client_chart', :layout => false
          return
        when 'idleness'
          render :partial => 'idleness_chart', :layout => false
          return
        end
      }
      format.json {
        case params[:chart]
        when 'client'
          clients = []
          months = []
          oldest = Client.find(:first, :order => 'created_at')
          if oldest
            start = Date.new(oldest.created_at.year, oldest.created_at.month, 1)
            next_month = Date.new(Time.now.year, Time.now.month, 1).next_month
            month = start
            while month != next_month
              # Combination of next_month and -1 gets us the last second of the month
              monthtime = Time.local(month.next_month.year, month.next_month.month) - 1
              clients << Client.count(:conditions => ["created_at <= ?", monthtime])
              months << "#{monthtime.strftime('%b')}\n#{monthtime.year}"
              month = month.next_month
            end
          end
          
          line_dot = LineDot.new
          line_dot.text = "Clients"
          line_dot.width = 1
          line_dot.colour = '#6363AC'
          line_dot.dot_size = 5
          line_dot.values = clients
          
          x = XAxis.new
          x.set_labels(months)
          
          y = YAxis.new
          # Set the top of the y scale to be the largest number of clients
          # rounded up to the nearest 10
          ymax = (clients.max.to_f / 10).ceil * 10
          ymax = 10 if ymax == 0  # In case there are no clients
          # Something around 10 divisions on the y axis looks decent
          ydiv = (ymax / 10).ceil
          y.set_range(0, ymax, ydiv)
          
          title = Title.new("Number of Clients")
          title.set_style('{font-size: 20px; color: #778877}')
          
          chart = OpenFlashChart.new
          chart.set_title(title)
          chart.x_axis = x
          chart.y_axis = y
          chart.bg_colour = '#FFFFFF'
          
          chart.add_element(line_dot)
          
          render :text => chart.to_s
          return
        when 'idleness'
          idlecounts = []
          percents = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
          percents.each do |percent|
            # 0%-100% is 101 steps so we need a special case to have the first
            # range in the graph be 0-10.  Remaining ranges will be 11-20,
            # 21-30, etc.
            if percent == 10
              idlecounts << Client.count(:conditions => ["idleness >= ? AND idleness <= ?", percent-10, percent])
            else
              idlecounts << Client.count(:conditions => ["idleness > ? AND idleness <= ?", percent-10, percent])
            end
          end
          
          x = XAxis.new
          x.set_labels(percents.collect{|p| "#{p}%"})
          
          y = YAxis.new
          # Set the top of the y scale to be the largest number of clients
          # rounded up to the nearest 10
          ymax = (idlecounts.max.to_f / 10).ceil * 10
          ymax = 10 if ymax == 0  # In case there are no clients
          # Something around 10 divisions on the y axis looks decent
          ydiv = (ymax / 10).ceil
          y.set_range(0, ymax, ydiv)
          
          title = Title.new("Likelihood of Idleness")
          title.set_style('{font-size: 20px; color: #778877}')
          
          bar = BarGlass.new
          bar.set_values(idlecounts)
          
          chart = OpenFlashChart.new
          chart.set_title(title)
          chart.x_axis = x
          chart.y_axis = y
          chart.bg_colour = '#FFFFFF'
          
          chart.add_element(bar)
          
          render :text => chart.to_s
          return
        end
      }
    end
  end
end
