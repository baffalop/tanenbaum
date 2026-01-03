open Import

module Cli = struct
  open Cmdliner

  module Terms = struct
    let year =
      let doc = "Run problems from year $(docv). Uses current year if omitted." in
      Arg.(value & opt (some int) None & info [ "year"; "y" ] ~docv:"YEAR" ~doc)

    let day =
      let doc = {|Run problem number "day" $(docv). Uses current day if omitted.|} in
      Arg.(value & opt (some int) None & info [ "day"; "d" ] ~docv:"DAY" ~doc)

    let part =
      let doc = "Run problem part $(docv). Defaults to part 1." in
      Arg.(value & opt int 1 & info [ "part"; "p" ] ~docv:"PART" ~doc)

    let auth_token =
      let doc =
        "Some operations require authenticating with adventofcode.com . This \
         is the token used for authentication."
      in
      let env = Cmd.Env.(info "AUTH_TOKEN" ~doc) in
      Arg.(
        value
        & opt (some string) None
        & info [ "auth_token" ] ~docv:"AUTH_TOKEN" ~doc ~env)

    let example =
      let doc =
        "Use the smaller example input in place of the real input. On first run, you'll need to pass this in via stdin."
      in
      Arg.(value & flag & info [ "example"; "x" ] ~docv:"EXAMPLE" ~doc)

    let submit =
      let doc =
        "If set, attempts to submit the problem output to adventofcode.com."
      in
      Arg.(value & flag & info [ "submit"; "s" ] ~docv:"SUBMIT" ~doc)
  end

  let run ~(year : int option) ~(day : int option) ~(part : int)
      ~example:(example : bool) ~submit:(submit : bool)
      ~token:(auth_token : string option) : unit Cmdliner.Term.ret =
      let output : (string, string) result =
        let@ (year, day) = match year, day with
          | Some year, Some day -> Ok (year, day)
          | _, _ ->
            let time = Unix.localtime @@ Unix.time () in
            let year = Option.value year ~default:(time.tm_year + 1900) in
            match day with
            | Some day -> Ok (year, day)
            | None ->
              if time.tm_mon != 11 then Error "Must specify --day if current date is not December"
              else Ok (year, time.tm_mday)
        in
        let@ run_mode : Problem_runner.Run_mode.t =
          match (auth_token, submit, example) with
          | _, true, true ->
              Error {|Cannot use --example and --submit together|}
          | None, true, _ ->
              Error {|Must provide AUTH_TOKEN when using --submit|}
          | _, _, true ->
            let input =
              (* It's a tty when no input is piped *)
              if Unix.isatty Unix.stdin then None
              else Some (In_channel.input_all In_channel.stdin)
            in
            Result.ok @@ Problem_runner.Run_mode.Example { input }
          | token, false, _ ->
            Result.ok @@ Problem_runner.Run_mode.Test_from_puzzle_input {
              credentials = Option.map Problem_runner.Credentials.of_auth_token token;
            }
          | Some token, true, _ ->
            Result.ok @@ Problem_runner.Run_mode.Submit {
              credentials = Problem_runner.Credentials.of_auth_token token;
            }
        in
        Problem_runner.(run { year; day; part; run_mode })
      in
      match output with
      | Ok output ->
          print_endline output;
          `Ok ()
      | Error error_msg -> `Error (false, error_msg)

let main () =
  let cmd_term =
    let open Cmdliner.Term.Syntax in
    let open Terms in
    let+ year and+ day and+ part and+ example and+ submit and+ auth_token in
    run ~year ~day ~part ~example ~submit ~token:auth_token
  in
  let cmd = Cmd.make (Cmd.info "aoc") @@ Cmdliner.Term.ret cmd_term in
  exit @@ Cmdliner.Cmd.eval cmd
end
