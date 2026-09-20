DiscourseAlumniMap::Engine.routes.draw do
    get "/" => "main#index"
    get "/export" => "main#export"
    get "/locations" => "main#locations"
    get "/state" => "main#state"
    get "/map-frame" => "main#map_frame"
    post "/action" => "main#mutate"
  end
