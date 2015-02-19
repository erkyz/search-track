app = angular.module('tabApp', ['ui.router', 'ui.bootstrap', 'angular-underscore'])

app.run ($rootScope, $state, $stateParams) ->
  $rootScope.$state = $state
  $rootScope.$stateParams = $stateParams

app.config ($stateProvider, $urlRouterProvider) ->

  $stateProvider
    .state('searches', {
      url: '/'
      templateUrl: '/dist/templates/tabPage/searches.html'
      controller: ($scope, $state, $http) ->
        updateFn = (apply) ->
          page_info = PageInfo.db({referrer: {isNull: false}}).get()
          # {query: [record, record,..], ...}
          grouped = _.groupBy page_info, (record) ->
            record.query
          
          # [{query, {url: [record, record, ...]}}, ...]
          grouped = _.object _.map grouped, (val,key) ->
            [key, _.groupBy val, (record) ->
              uri = new URI(record.url)
              hash = uri.hash()
              if (hash)
                uri.hash("")
                record.hash = hash
              return uri.toString()
            ]

          grouped = _.object _.map grouped, (val, key) ->
            [key, {records: val, lda: SearchInfo.db({name: key}).first().lda}]

          if !apply
            $scope.$apply () ->
              $scope.pages = _.pick grouped, (val, key, obj) ->
                key.length > 2
          else
            $scope.pages = _.pick grouped, (val, key, obj) ->
              key.length > 2
        updateFn(true)
        # SearchInfo.updateFunction(updateFn)
        PageInfo.updateFunction(updateFn)          
      })
    .state('tree', {
      url: '/tree'
      templateUrl: '/dist/templates/tabPage/tree.html'
      controller: ($scope, $state) ->
        #Get our list of queries
        queryUpdate = () ->
          $scope.$apply () ->
            $scope.queries = SearchInfo.db().get()
        $scope.queries = SearchInfo.db().get()
        $scope.query = $scope.queries[0]
        #Initialize everything for d3
        d3_tree.init_vis()
        toggleAll = (d) ->
          if d.children
            d.children.forEach(toggleAll)
            d3_tree.toggle(d)
            
        updateFn = () ->
          page_info = PageInfo.db({query: $scope.query.name}, {referrer: {isNull: false}}).get()
          #Root is the one without the referrer
          d3_tree.root = PageInfo.db({query: $scope.query.name}, {referrer: {isNull: true}}).first()
          d3_tree.root.children = [] 
          d3_tree.root.x0 = d3_tree.h/2
          d3_tree.root.y0 = 0
          d3_tree.root.name = d3_tree.root.query
          
          _.each page_info, (record) ->
            record.children = []
            
          _.each page_info, (record) ->
            #uri = new URI(record.url)
            record.name = record.url
            referrer = _.find page_info, (item) ->
              item.___id == record.referrer
            if referrer?
              referrer.children.push(record)
            else
              d3_tree.root.children.push(record)

          
          d3_tree.root.children.forEach(toggleAll)
          d3_tree.update d3_tree.root  
        
        updateFn()
        SearchInfo.updateFunction(queryUpdate)
        PageInfo.updateFunction(updateFn)
        $scope.$watch 'query', (newVal, oldVal) ->
          updateFn()
      })
    .state('graph', {
      url: '/graph'
      templateUrl: '/dist/templates/tabPage/graph.html'
      controller: ($scope, $state) ->
        #Get our list of queries
        updateFn = () ->
          queries = SearchInfo.db({name: {'!is': ''}, lda_vector: {isNull: false}}).get()
          console.log queries

          graph = {nodes: [], links: []}
          i = 0
          _.each queries, (query) ->
            graph.nodes.push {name: query.name, group: i++, info: query, size: PageInfo.db({query: query.name}).get().length}

          dot = (v1, v2) ->
            v = _.map _.zip(v1, v2), (xy) -> xy[0] * xy[1]
            v = _.reduce v, (x, y) -> x + y
            v

          mag = (v) ->
            v = _.map v, (x) -> x*x
            out = _.reduce v, (x, y) -> x + y
            Math.sqrt(out)
            
          cosine = (v1, v2) ->
            dot(v1, v2) / (mag(v1) * mag(v2))

          _.each graph.nodes, (node1) ->
            _.each graph.nodes, (node2) ->
              if node2.group > node1.group
                similarity = cosine(node1.info.lda_vector, node2.info.lda_vector)
                graph.links.push {source: node1.group, target: node2.group, value: similarity}

          width = 1280
          height = 800
          color = d3.scale.category20()

          force = d3.layout.force()
              .charge(1000)
              .friction(0.01)
              .linkDistance (l) -> Math.pow(1.0 - l.value, 1) * 500
              .size([width, height])

          real_svg = d3.select("#graph").append("svg")
          svg = real_svg.append("g")
          current_scale = 1
          current_translate = [0, 0]
          zoom = d3.behavior.zoom()
                  .scaleExtent([0.1, 10])
                  .on("zoom", () ->
                    console.log 'onZoom'
                    console.log d3.event.translate
                    console.log d3.event.scale
                    svg.attr("transform", "translate(" + d3.event.translate + ")scale(" + d3.event.scale + ")")
                    current_scale = d3.event.scale
                    current_translate = d3.event.translate
                  ).center(null)
          real_svg.call(zoom).on('mousedown.zoom',null)

          fixPoint = (point) ->
            {x: (point.x * current_scale) + current_translate[0], y: (point.y * current_scale) + current_translate[1]}

          pointInPolygon = (point, path) ->
            # ray-casting algorithm based on
            # http://www.ecse.rpi.edu/Homepages/wrf/Research/Short_Notes/pnpoly.html
            
            point = fixPoint(point)

            x = point.x
            y = point.y
            
            inside = false
            i = 0
            j = path.length - 1
            while (i < path.length)
              xi = path[i].x
              yi = path[i].y
              xj = path[j].x
              yj = path[j].y
              
              intersect = ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
              if (intersect)
                inside = !inside
              j = i++
            
            return inside

          inPoly = false
          lineData = []
          mousedown = () ->
            if (d3.event.shiftKey)
              console.log 'mouse down'
              inPoly = true
          mousemove = () ->
            if not inPoly
              return
            xy = d3.mouse(this)
            lineData.push {x: xy[0], y: xy[1]}
            force.start()
          mouseup = () ->
            console.log 'mouse up'
            inPoly = false
            node.each((d) ->
              d3.select(this).classed("selected", d.selected = pointInPolygon({x: d.x, y: d.y}, lineData))
            )
            lineData = []
            force.start()

          real_svg.attr("width", width)
              .attr("height", height)
              .on('mousedown', mousedown)
              .on('mousemove', mousemove)
              .on('mouseup', mouseup)


          lineFunction = d3.svg.line()
                        .x((d) -> d.x )
                        .y((d) -> d.y )
                        .interpolate("basis-closed")

          polygon = real_svg.append('path')
                .attr('stroke', 'lightblue')
                .attr('stroke-width', 3)
                .attr('fill', 'rgba(0,0,0,0.1)')

          node = svg.selectAll(".node")
          link = svg.selectAll(".link")
          text = svg.selectAll("text.label")
          pin = svg.selectAll(".pin")

          force.nodes(graph.nodes)
              .links(graph.links)
              .on("tick", () ->
                link.attr("x1", (d) -> d.source.x)
                    .attr("y1", (d) -> d.source.y)
                    .attr("x2", (d) -> d.target.x)
                    .attr("y2", (d) -> d.target.y)

                node.attr("cx", (d) -> d.x )
                    .attr("cy", (d) -> d.y )

                text.attr("transform", (d) ->
                  "translate(" + (d.x + (2.5*d.size) + 5) + "," + (d.y + 3) + ")"
                )
                pin.attr("transform", (d) ->
                  "translate(" + (d.x-2) + "," + (d.y-2) + ")"
                )
                .attr("width", (d) ->
                  if d.fixed and not d.dragging
                    return 4
                  return 0
                )
                .attr("height", (d) ->
                  if d.fixed and not d.dragging
                    return 4
                  return 0
                )
                polygon.attr('d', lineFunction(lineData))
            )

          wasDragging = false
          drag = force.drag()
            .on("drag", (d) ->
              console.log 'onDrag'
              wasDragging = true
              d.dragging = true
              if (!d3.event.sourceEvent.shiftKey)
                d3.select(this).classed("fixed", d.fixed = true)
            )
            .on("dragend", (d) ->
              console.log 'onDragEnd'
              d.dragging = false
              if (wasDragging and d3.event.sourceEvent.shiftKey)
                d3.select(this).classed("fixed", d.fixed = false)
              wasDragging = false
            )

          render = () ->

            console.log 'render'
            console.log graph.nodes
            console.log 'render'

            link = link.data(graph.links)
            link.enter().append("line")
                .attr("class", "link")
                .style("stroke-width", (d) -> 
                  if d.value > 0.2
                    Math.pow(d.value, 2) * 3 
                  else
                    0
                )

            node = node.data(graph.nodes)
            node.enter().append("circle")
                .attr("class", "node")
                .attr("r", (d) -> 2.5 * d.size)
                .style("fill", (d) -> color(d.group) )
                .call(drag)
                .on('click', (d) ->
                  console.log 'onClick'
                  if (d3.event.defaultPrevented)
                    console.log 'onClick no'
                    return
       
                  if (!d3.event.shiftKey)
                    was_selected = d.selected
                    node.classed("selected", (p) -> p.selected =  p.previouslySelected = false)
                    d3.select(this).classed("selected", d.selected = !was_selected)
                  else
                    was_selected = d.selected
                    d3.select(this).classed("selected", d.selected = !d.previouslySelected)
                    d3.select(this).classed("selected", d.selected = !was_selected)
                )

            text = text.data(graph.nodes)
            text.enter().append("text")
                  .attr("class", "label")
                  .attr("fill", (d) -> color(d.group))
                  .attr('stroke', 'lightgray')
                  .attr('stroke-width', 0.5)
                  .text((d) -> d.name + " (" + d.size + ")")

            pin = pin.data(graph.nodes)
            pin.enter().append("rect")
                .attr("x", 0)
                .attr("y", 0)
                .attr("class", "pin")
                .style("fill", 'black')
                .call(drag)

          render()
          force.start()
          
        updateFn()
      })
    .state('settings', {
      url: '/settings'
      templateUrl: '/dist/templates/tabPage/settings.html'
      controller: ($scope, $state, $modal) ->
        $scope.openDeleteModal = () ->
          modalInstance = $modal.open {
            templateUrl: 'deleteContent.html',
            size: 'sm',
            controller: 'removeModal'
          }
        
      })

  $urlRouterProvider.otherwise('/')

app.controller 'MainCtrl', ($scope, $rootScope, $state) ->
  $scope.getDomain = (str) ->
    matches = str.match(/^https?\:\/\/([^\/:?#]+)(?:[\/:?#]|$)/i)
    return matches && matches[1]

  
app.controller 'removeModal', ($scope, $modalInstance) ->
  
  $scope.ok = () ->
    PageInfo.clearDB()
    SearchInfo.clearDB()
    $modalInstance.close('cleared')
    
  $scope.cancel = () ->
    $modalInstance.close('canceled')
  ###
    if $cookies.state?
    $scope.$evalAsync (scope) ->
      $state.go($cookies.state)
  ###

  
