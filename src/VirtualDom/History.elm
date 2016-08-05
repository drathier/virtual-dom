module VirtualDom.History exposing
  ( History
  , empty
  , size
  , add
  , get
  , view
  )


import Array exposing (Array)
import Json.Decode as Decode
import Json.Encode as Encode
import Native.Debug
import VirtualDom as VDom exposing (Node)



-- CONSTANTS


maxSnapshotSize : Int
maxSnapshotSize =
  64



-- HISTORY


type alias History model msg =
  { snapshots : Array (Snapshot model msg)
  , recent : RecentHistory model msg
  , numMessages : Int
  }


type alias RecentHistory model msg =
  { model : model
  , messages : List msg
  , numMessages : Int
  }


type alias Snapshot model msg =
  { model : model
  , messages : Array msg
  }


empty : model -> History model msg
empty model =
  History Array.empty (RecentHistory model [] 0) 0


size : History model msg -> Int
size history =
  history.numMessages



-- ADD MESSAGES


add : msg -> model -> History model msg -> History model msg
add msg model { snapshots, recent, numMessages } =
  case addRecent msg model recent of
    (Just snapshot, newRecent) ->
      History (Array.push snapshot snapshots) newRecent (numMessages + 1)

    (Nothing, newRecent) ->
      History snapshots newRecent (numMessages + 1)


addRecent
  : msg
  -> model
  -> RecentHistory model msg
  -> ( Maybe (Snapshot model msg), RecentHistory model msg )
addRecent msg newModel { model, messages, numMessages } =
  if numMessages == maxSnapshotSize then
    ( Just (Snapshot model (Array.fromList messages))
    , RecentHistory newModel [msg] 1
    )

  else
    ( Nothing
    , RecentHistory model (msg :: messages) (numMessages + 1)
    )



-- GET SUMMARY


get : (msg -> model -> (model, a)) -> Int -> History model msg -> ( model, msg )
get update index { snapshots, recent, numMessages } =
  let
    snapshotMax =
      numMessages - recent.numMessages
  in
    if index >= snapshotMax then
      undone <|
        List.foldr (getHelp update) (Stepping (index - snapshotMax) recent.model) recent.messages

    else
      case Array.get (index // maxSnapshotSize) snapshots of
        Nothing ->
          Debug.crash "UI should only let you ask for real indexes!"

        Just { model, messages } ->
          undone <|
            Array.foldr (getHelp update) (Stepping (rem index maxSnapshotSize) model) messages


type GetResult model msg
  = Stepping Int model
  | Done msg model


getHelp : (msg -> model -> (model, a)) -> msg -> GetResult model msg -> GetResult model msg
getHelp update msg getResult =
  case getResult of
    Done _ _ ->
      getResult

    Stepping n model ->
      if n == 0 then
        Done msg (fst (update msg model))

      else
        Stepping (n - 1) (fst (update msg model))


undone : GetResult model msg -> ( model, msg )
undone getResult =
  case getResult of
    Done msg model ->
      ( model, msg )

    Stepping _ _ ->
      Debug.crash "Bug in History.get"



-- VIEW


view : Maybe Int -> History model msg -> Node Int
view maybeIndex { snapshots, recent, numMessages } =
  let
    index =
      Maybe.withDefault -1 maybeIndex

    oldStuff =
      VDom.lazy2 viewSnapshots index snapshots

    newStuff =
      snd <| List.foldl (consMsg index) (numMessages - 1, []) recent.messages
  in
    div [ class "debugger-sidebar-messages" ] (oldStuff :: newStuff)


div =
  VDom.node "div"


class name =
  VDom.property "className" (Encode.string name)



-- VIEW SNAPSHOTS


viewSnapshots : Int -> Array (Snapshot model msg) -> Node Int
viewSnapshots currentIndex snapshots =
  let
    highIndex =
      maxSnapshotSize * Array.length snapshots
  in
    div [] <| snd <|
      Array.foldr (consSnapshot currentIndex) (highIndex, []) snapshots


consSnapshot : Int -> Snapshot model msg -> ( Int, List (Node Int) ) -> ( Int, List (Node Int) )
consSnapshot currentIndex snapshot (index, rest) =
  let
    nextIndex =
      index - maxSnapshotSize

    currentIndexHelp =
      if nextIndex <= currentIndex && currentIndex < index then currentIndex else -1
  in
    ( index - maxSnapshotSize
    , VDom.lazy3 viewSnapshot currentIndexHelp index snapshot :: rest
    )


viewSnapshot : Int -> Int -> Snapshot model msg -> Node Int
viewSnapshot currentIndex index { messages } =
  div [] <| snd <|
    Array.foldl (consMsg currentIndex) (index - 1, []) messages



-- VIEW MESSAGE


consMsg : Int -> msg -> ( Int, List (Node Int) ) -> ( Int, List (Node Int) )
consMsg currentIndex msg (index, rest) =
  ( index - 1
  , VDom.lazy3 viewMessage currentIndex index msg :: rest
  )


viewMessage : Int -> Int -> msg -> Node Int
viewMessage currentIndex index msg =
  let
    className =
      if currentIndex == index then
        "messages-entry messages-entry-selected"

      else
        "messages-entry"
  in
    div
      [ class className
      , VDom.on "click" (Decode.succeed index)
      ]
      [ VDom.text (Native.Debug.messageToString msg)
      ]