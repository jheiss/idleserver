jQuery ->
  $.getJSON $("#idleness_chart").data("url"), (data) ->
    $.plot $("#idleness_chart"), data,
      {
        # Note that barWidth is in x-axis units
        series: {bars: {show: true, barWidth: 10}},
        # For consistency with the next graph put the legend in the same place
        legend: {position: 'nw'}
      }
  
  $.getJSON $("#client_chart").data("url"), (data) ->
    $.plot $("#client_chart"), data,
      {
        series: {lines: {show: true}, points: {show: true }},
        xaxis: {mode: "time"},
        # In most environments the client count increases over time, so there's more
        # likely to be whitespace in the upper left than the upper right
        legend: {position: 'nw'},
        grid: {hoverable: true} }
  
  showTooltip = (x, y, contents) ->
    $('<div id="tooltip">' + contents + '</div>').css( {
        position: 'absolute',
        display: 'none',
        top: y + 5,
        left: x + 5,
        border: '1px solid #fdd',
        padding: '2px',
        'background-color': '#fee',
        opacity: 0.80
    }).appendTo("body").fadeIn(200)
  
  previousPoint = null
  monthNames = [ "January", "February", "March", "April", "May", "June",
                 "July", "August", "September", "October", "November", "December" ]
  $("#client_chart").bind "plothover", (event, pos, item) ->
    $("#x").text pos.x.toFixed(2)
    $("#y").text pos.y.toFixed(2)
    if item
      if previousPoint != item.dataIndex
        previousPoint = item.dataIndex
        $("#tooltip").remove()
        d = new Date(item.datapoint[0])
        showTooltip(item.pageX, item.pageY,
                    monthNames[d.getMonth()] + " " + d.getDate() + " " + d.getFullYear() + ": " + item.datapoint[1] + " clients")
    else
      $("#tooltip").remove()
      previousPoint = null
