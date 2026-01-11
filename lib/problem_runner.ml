open Import

module Credentials : sig
  type t

  val of_auth_token : string -> t
  val to_headers : t -> (string * string) list
end = struct
  type t = string

  let of_auth_token (x : string) : t = x

  let to_headers (t : t) : (string * string) list = [ ("Cookie", "session=" ^ t) ]
end

module Cache : sig
  type t

  val init : year:int -> basename:string -> t
  val exists : t -> bool
  val read : t -> string
  val write : t -> string -> unit
  val path : t -> string
end = struct
  type t = { filename : string }

  let init ~(year : int) ~(basename : string) : t =
    if not (Sys.file_exists "inputs") then Sys.mkdir "inputs" 0o777;
    let year_dir = Filename.concat "inputs" @@ string_of_int year in
    if not (Sys.file_exists year_dir) then Sys.mkdir year_dir 0o777;
    let filename = Filename.concat year_dir @@ basename ^ ".txt" in
    { filename }

  let exists ({ filename } : t) = Sys.file_exists filename

  let read ({ filename } : t) =
    In_channel.with_open_text filename @@ fun ch ->
    really_input_string ch (in_channel_length ch)

  let write ({ filename } : t) (contents : string) =
    Out_channel.with_open_bin filename @@ fun ch ->
    output_string ch contents

  let path ({ filename } : t) = filename
end

module Run_mode = struct
  type t =
    | Example of { input : string option }
    | Test_from_puzzle_input of { credentials : Credentials.t option }
    | Submit of { credentials : Credentials.t }

  let get_example_input ~year:(year : int) ~day:(day : int) (input : string option) : (string, string) result =
    let cache = Cache.init ~year ~basename:(Format.sprintf "%02d-ex" day) in
    match input with
    | Some input -> (
      Cache.write cache input;
      Ok input
    )
    | None ->
      if Cache.exists cache then Ok (Cache.read cache)
      else Error "No example input in cache: please pass in via stdin"

  let get_puzzle_input (year : int) (day : int)
      (credentials : Credentials.t option) : (string, string) result =
    let cache = Cache.init ~year ~basename:(Format.sprintf "%02d" day) in
    if Cache.exists cache then Ok (Cache.read cache)
    else match credentials with
    | None ->
        Error "Cannot fetch input from adventofcode.com: missing credentials."
    | Some credentials ->
        Result.map_error (fun (code, msg) ->
          Printf.sprintf "[Code %d] %s" (Curl.int_of_curlCode code) msg)
        @@ Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        let url = Printf.sprintf "https://adventofcode.com/%d/day/%d/input" year day in
        let headers = Credentials.to_headers credentials in
        let@ { body } = Ezcurl.get ~url ~headers () in
        Cache.write cache body;
        Printf.printf "Got input; wrote to %s\n" @@ Cache.path cache;
        Result.ok body

  let get_input ~(year : int) ~(day : int) : t -> (string, string) result =
    function
    | Example { input } -> get_example_input ~year ~day input
    | Test_from_puzzle_input { credentials } ->
        get_puzzle_input year day credentials
    | Submit { credentials } -> get_puzzle_input year day (Some credentials)

  let cleanup (year : int) (day : int) (part : int) (output : string)
      (run_mode : t) : (string option, string) result =
    match run_mode with
    | Test_from_puzzle_input _ | Example _ -> Ok None
    | Submit { credentials } ->
        Result.map_error (fun (code, msg) ->
          Printf.sprintf "[Code %d] %s" (Curl.int_of_curlCode code) msg)
        @@ Eio_main.run
        @@ fun env ->
        Eio.Switch.run
        @@ fun sw ->
        let url = Printf.sprintf "https://adventofcode.com/%d/day/%d/answer" year day in
        let headers = Credentials.to_headers credentials
          @ [ ("Content-Type", "application/x-www-form-urlencoded") ]
        in
        let content = `String (Printf.sprintf "level=%d&answer=%s" part output) in
        let@ res = Ezcurl.post ~url ~headers ~content ~params:[] () in
        Result.ok @@ Some res.body
end

module Options = struct
  type t = { year : int; day : int; part : int; run_mode : Run_mode.t }
end

let run_problem (module Problem : Problem.T) (run_mode : Run_mode.t)
    (year : int) (day : int) (part : int) : (string, string) result =
  let@ input = Run_mode.get_input ~year ~day run_mode in
  let@ result =
    match part with
    | 1 -> Problem.Part_1.run input
    | 2 -> Problem.Part_2.run input
    | p -> Error (Format.sprintf {|Invalid part "%d". Expected "1" or "2".|} p)
  in
  let@ cleanup_result = Run_mode.cleanup year day part result run_mode in
  let () =
    match cleanup_result with None -> () | Some result -> print_endline result
  in
  Ok result

let find_problem (year : int) (day : int) :
    ((module Problem.T), string) result =
  match
    Problems.All.all
    |> List.find_opt (fun (module Problem : Problem.T) -> Problem.year = year && Problem.day = day)
  with
  | Some p -> Ok p
  | None -> Error (Format.sprintf "Problem (year = %d, day = %d) not implemented." year day)

let run (options : Options.t) : (string, string) result =
  let@ problem = find_problem options.year options.day in
  run_problem problem options.run_mode options.year options.day options.part
