(**************************************************************************)
(*                                BELENIOS                                *)
(*                                                                        *)
(*  Copyright © 2012-2021 Inria                                           *)
(*                                                                        *)
(*  This program is free software: you can redistribute it and/or modify  *)
(*  it under the terms of the GNU Affero General Public License as        *)
(*  published by the Free Software Foundation, either version 3 of the    *)
(*  License, or (at your option) any later version, with the additional   *)
(*  exemption that compiling, linking, and/or using OpenSSL is allowed.   *)
(*                                                                        *)
(*  This program is distributed in the hope that it will be useful, but   *)
(*  WITHOUT ANY WARRANTY; without even the implied warranty of            *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *)
(*  Affero General Public License for more details.                       *)
(*                                                                        *)
(*  You should have received a copy of the GNU Affero General Public      *)
(*  License along with this program.  If not, see                         *)
(*  <http://www.gnu.org/licenses/>.                                       *)
(**************************************************************************)

open Lwt.Syntax
open Belenios_platform.Platform
open Belenios_core.Common
open Belenios_core.Serializable_builtin_t
open Belenios_core.Serializable_j
open Belenios_core.Signatures
open Belenios
open Belenios_api.Serializable_j
open Web_serializable_builtin_t
open Web_serializable_j
open Web_common
open Api_generic

let with_administrator token se f =
  let@ token = Option.unwrap unauthorized token in
  match lookup_token token with
  | Some a when Accounts.check a se.se_owners -> f a
  | _ -> not_found

let with_administrator_or_credential_authority token se f =
  let@ token = Option.unwrap unauthorized token in
  if token = se.se_public_creds then (
    f `CredentialAuthority
  ) else (
    match lookup_token token with
    | Some a when Accounts.check a se.se_owners -> f (`Administrator a)
    | _ -> not_found
  )

let with_administrator_or_credential_authority_or_trustee token se f =
  let@ token = Option.unwrap unauthorized token in
  if token = se.se_public_creds then (
    f `CredentialAuthority
  ) else (
    let@ () = fun cont ->
      match se.se_trustees with
      | `Basic x ->
         begin
           match List.find_opt (fun x -> x.st_token = token) x.dbp_trustees with
           | Some _ -> f `Trustee
           | None -> cont ()
         end
      | `Threshold x ->
         begin
           match List.find_opt (fun x -> x.stt_token = token) x.dtp_trustees with
           | Some _ -> f `Trustee
           | None -> cont ()
         end
    in
    match lookup_token token with
    | Some a when Accounts.check a se.se_owners -> f (`Administrator a)
    | _ -> not_found
  )

let with_threshold_trustee token se f =
  let@ token = Option.unwrap unauthorized token in
  match se.se_trustees with
  | `Basic _ -> not_found
  | `Threshold t ->
     match List.find_opt (fun x -> x.stt_token = token) t.dtp_trustees with
     | Some x -> f (x, t)
     | None -> not_found

let get_authentication se =
  match se.se_metadata.e_auth_config with
  | Some [{auth_system = "password"; _}] -> `Password
  | Some [{auth_system = "cas"; auth_config; _}] -> `CAS (List.assoc "server" auth_config)
  | Some [{auth_system = "import"; auth_instance; _}] -> `Configured auth_instance
  | _ -> raise (Error "invalid authentication")

let auth_config_of_authentication = function
  | `Password -> {auth_system = "password"; auth_instance = "password"; auth_config = []}
  | `CAS server -> {auth_system = "cas"; auth_instance = "cas"; auth_config = ["server", server]}
  | `Configured auth_instance -> {auth_system = "import"; auth_instance; auth_config = []}

let api_of_draft se =
  let draft_questions =
    {
      se.se_questions with
      t_credential_authority = Some (Option.value se.se_metadata.e_cred_authority ~default:"");
      t_administrator = Some (Option.value se.se_administrator ~default:"");
    }
  in
  Lwt.return {
    draft_version = se.se_version;
    draft_owners = se.se_owners;
    draft_questions;
    draft_languages = Option.value se.se_metadata.e_languages ~default:[];
    draft_contact = se.se_metadata.e_contact;
    draft_booth = Option.value se.se_metadata.e_booth_version ~default:1;
    draft_authentication = get_authentication se;
    draft_group = se.se_group;
  }

let assert_ msg b f =
  if b then f () else raise (Error msg)

let draft_of_api a se d =
  let version = se.se_version in
  let () =
    if d.draft_version <> version then
      raise (Error "cannot change version")
  in
  let@ () = assert_ "invalid booth version" (List.mem d.draft_booth supported_booth_versions) in
  let@ () = assert_ "there must be at least one language" (List.length d.draft_languages >= 1) in
  let@ () = assert_ "you must be in owners" (List.mem a.account_id d.draft_owners) in
  let e_cred_authority = d.draft_questions.t_credential_authority in
  let () =
    let old = se.se_metadata.e_cred_authority in
    if e_cred_authority <> old then
      if se.se_public_creds_received && (old = Some "server" || e_cred_authority = Some "server") then
        raise (Error "credential authority change not allowed")
  in
  let se_group = d.draft_group in
  let () =
    let old = se.se_group in
    if se_group <> old then (
      if se.se_public_creds_received then
        raise (Error "the group cannot be changed")
      else (
        try
          let module G = (val Group.of_string ~version se_group) in
          ()
        with _ ->
          raise (Error "invalid group")
      )
    )
  in
  let () =
    let has_nh_questions =
      Array.exists
        (function Belenios_core.Question.NonHomomorphic _ -> true | _ -> false)
        d.draft_questions.t_questions
    in
    if has_nh_questions then (
      match se_group with
      | "RFC-3526-2048" -> ()
      | _ -> raise (Error "a NH group is required for these questions")
    )
  in
  let se_metadata =
    {
      se.se_metadata with
      e_contact = d.draft_contact;
      e_languages = Some d.draft_languages;
      e_booth_version = Some d.draft_booth;
      e_cred_authority;
      e_auth_config = Some [auth_config_of_authentication d.draft_authentication];
    }
  in
  {
    se with
    se_metadata;
    se_owners = d.draft_owners;
    se_questions = d.draft_questions;
    se_administrator = d.draft_questions.t_administrator;
    se_group;
  }

let delete_draft uuid =
  let* () = rmdir !!(raw_string_of_uuid uuid) in
  Web_persist.clear_elections_by_owner_cache ()

let generate_uuid () =
  let length = !Web_config.uuid_length in
  let* token = generate_token ?length () in
  Lwt.return (uuid_of_raw_string token)

let post_drafts account draft =
  let@ () = fun cont ->
    if !Web_config.deny_newelection then
      Lwt.return_none
    else
      Lwt.(cont () >>= return_some)
  in
  let owners = [account.account_id] in
  let* uuid = generate_uuid () in
  let* token = generate_token () in
  let se_metadata =
    {
      e_owners = owners;
      e_auth_config = None;
      e_cred_authority = None;
      e_trustees = None;
      e_languages = None;
      e_contact = None;
      e_booth_version = None;
    }
  in
  let se_questions =
    {
      t_description = "";
      t_name = "";
      t_questions = [||];
      t_administrator = None;
      t_credential_authority = None;
    }
  in
  let se =
    {
      se_version = List.hd supported_crypto_versions;
      se_owners = owners;
      se_group = !Web_config.default_group;
      se_voters = [];
      se_questions;
      se_trustees = `Basic {dbp_trustees = []};
      se_metadata;
      se_public_creds = token;
      se_public_creds_received = false;
      se_creation_date = Some (now ());
      se_administrator = None;
    }
  in
  let se = draft_of_api account se draft in
  let* () = Lwt_unix.mkdir !!(raw_string_of_uuid uuid) 0o700 in
  let* () = Web_persist.set_draft_election uuid se in
  let* () = Web_persist.clear_elections_by_owner_cache () in
  Lwt.return uuid

let get_draft_voters se =
  se.se_voters
  |> List.map (fun x -> x.sv_id)

let put_draft_voters uuid se voters =
  let existing_voters =
    List.fold_left (fun accu v -> SMap.add v.sv_id v accu) SMap.empty se.se_voters
  in
  let se_voters =
    List.map
      (fun sv_id ->
        match SMap.find_opt sv_id existing_voters with
        | None -> {sv_id; sv_password = None}
        | Some x -> x
      ) voters
  in
  let* total_weight, _, _ =
    Lwt_list.fold_left_s
      (fun (total_weight, shape, voters) {sv_id; _} ->
        if not (is_identity sv_id) then (
          Lwt.fail @@ Error (Printf.sprintf "invalid identity: %s" sv_id)
        ) else (
          let address, login, weight = split_identity_opt sv_id in
          let* () =
            match shape, login with
            | Some (true, _), None -> Lwt.fail @@ Error (Printf.sprintf "missing login in %s" sv_id)
            | Some (false, _), Some _ -> Lwt.fail @@ Error (Printf.sprintf "extra login in %s" sv_id)
            | _ -> Lwt.return_unit
          in
          let* () =
            match shape, weight with
            | Some (_, true), None -> Lwt.fail @@ Error (Printf.sprintf "missing weight in %s" sv_id)
            | Some (_, false), Some _ -> Lwt.fail @@ Error (Printf.sprintf "extra weight in %s" sv_id)
            | _ -> Lwt.return_unit
          in
          let shape =
            match shape with
            | Some _ -> shape
            | None -> Some ((login <> None), (weight <> None))
          in
          let login = String.lowercase_ascii (Option.value login ~default:address) in
          let* voters =
            if SSet.mem login voters then (
              Lwt.fail @@ Error (Printf.sprintf "duplicate login in %s" sv_id)
            ) else (
              Lwt.return (SSet.add login voters)
            )
          in
          let weight = Option.value weight ~default:Weight.one in
          Lwt.return (Weight.(total_weight + weight), shape, voters)
        )
      ) (Weight.zero, None, SSet.empty) se_voters
  in
  let* () =
    let expanded = Weight.expand ~total:total_weight total_weight in
    if Z.compare expanded Weight.max_expanded_weight > 0 then (
      Lwt.fail @@ Error (Printf.sprintf "expanded total weight too big: %s/%s" (Z.to_string expanded) (Z.to_string Weight.max_expanded_weight))
    ) else (
      Lwt.return_unit
    )
  in
  let se = {se with se_voters} in
  Web_persist.set_draft_election uuid se

let get_draft_passwords se =
  se.se_voters
  |> List.filter_map (fun x -> Option.map (fun _ -> x.sv_id) x.sv_password)

let post_draft_passwords generate uuid se voters =
  let se_voters =
    List.fold_left (fun accu v -> SMap.add v.sv_id v accu) SMap.empty se.se_voters
  in
  let () =
    if SMap.cardinal se_voters > !Web_config.maxmailsatonce then
      raise (Error "too many voters")
  in
  let voters =
    List.map
      (fun id ->
        match SMap.find_opt id se_voters with
        | None -> raise (Error (Printf.sprintf "voter not in voter list: %s" id))
        | Some v -> v
      ) voters
  in
  let* jobs =
    Lwt_list.fold_left_s
      (fun jobs v ->
        let* job, x = generate se.se_metadata v.sv_id in
        v.sv_password <- Some x;
        Lwt.return (job :: jobs)
      ) [] voters
  in
  let* () = Web_persist.set_draft_election uuid se in
  Lwt.return jobs

let split_private_credential x =
  match String.split_on_char ' ' x with
  | [pc_voter; pc_credential] -> Some {pc_voter; pc_credential}
  | _ -> None

let get_draft_credentials who uuid se =
  let credentials_token =
    if se.se_metadata.e_cred_authority = Some "server" then
      None
    else
      Some se.se_public_creds
  in
  let* credentials_public =
    let* x = read_file_single_line ~uuid "public_creds.json" in
    let&* x in
    Lwt.return_some (public_credentials_of_string x)
  in
  let* credentials_private =
    match who with
    | `Administrator _ ->
       let* x = read_file ~uuid "private_creds.txt" in
       Option.map (List.filter_map split_private_credential) x
       |> Lwt.return
    | `CredentialAuthority -> Lwt.return_none
  in
  Lwt.return {credentials_token; credentials_public; credentials_private}

type generate_credentials_on_server_error =
  [ `NoVoters
  | `TooManyVoters
  | `Already
  | `NoServer
  ]

module CG = Belenios_core.Credential.MakeGenerate (LwtRandom)

let generate_credentials_on_server send uuid se =
  let nvoters = List.length se.se_voters in
  if nvoters > !Web_config.maxmailsatonce then
    Lwt.return (Stdlib.Error `TooManyVoters)
  else if nvoters = 0 then
    Lwt.return (Stdlib.Error `NoVoters)
  else if se.se_public_creds_received then
    Lwt.return (Stdlib.Error `Already)
  else if se.se_metadata.e_cred_authority <> Some "server" then
    Lwt.return (Stdlib.Error `NoServer)
  else (
    let show_weight =
      List.exists
        (fun v ->
          let _, _, weight = split_identity_opt v.sv_id in
          weight <> None
        ) se.se_voters
    in
    let version = se.se_version in
    let module G = (val Group.of_string ~version se.se_group : GROUP) in
    let module CMap = Map.Make (G) in
    let module CD = Belenios_core.Credential.MakeDerive (G) in
    let* public_creds, private_creds, jobs =
      Lwt_list.fold_left_s (fun (public_creds, private_creds, jobs) v ->
          let recipient, login, weight = split_identity v.sv_id in
          let* credential = CG.generate () in
          let pub_cred =
            let x = CD.derive uuid credential in
            G.(g **~ x)
          in
          let* job = send ~recipient ~login ~weight ~credential in
          Lwt.return (CMap.add pub_cred weight public_creds, (v.sv_id, credential) :: private_creds, job :: jobs)
        ) (CMap.empty, [], []) se.se_voters
    in
    let private_creds = List.rev_map (fun (id, c) -> id ^ " " ^ c) private_creds in
    let* () = write_file ~uuid "private_creds.txt" private_creds in
    let public_creds =
      CMap.bindings public_creds
      |> List.map
           (fun (cred, weight) ->
             let cred = G.to_string cred in
             if show_weight then
               Printf.sprintf "%s,%s" cred (Weight.to_string weight)
             else cred
           )
    in
    let public_creds = string_of_public_credentials public_creds in
    let* () = write_file ~uuid "public_creds.json" [public_creds] in
    se.se_public_creds_received <- true;
    let* () = Web_persist.set_draft_election uuid se in
    Lwt.return (Ok jobs)
  )

let exn_of_generate_credentials_on_server_error = function
  | `NoVoters -> Error "no voters"
  | `TooManyVoters -> Error "too many voters"
  | `Already -> Error "already done"
  | `NoServer -> Error "credential authority is not the server"

let submit_public_credentials uuid se credentials =
  let () = if se.se_voters = [] then raise (Error "No voters") in
  let version = se.se_version in
  let module G = (val Group.of_string ~version se.se_group : GROUP) in
  let weights =
    List.fold_left
      (fun (i, weights) x ->
        try
          let x, w = extract_weight x in
          let x = G.of_string x in
          if not (G.check x) then raise Exit;
          i + 1, w :: weights
        with _ ->
          raise (Error (Printf.sprintf "invalid credential at index %d" i))
      ) (0, []) credentials
    |> (fun (_, weights) -> List.sort Weight.compare weights)
  in
  let expected_weights =
    List.fold_left
      (fun accu {sv_id; _} ->
        let _, _, weight = split_identity sv_id in
        weight :: accu
      ) [] se.se_voters
    |> List.sort Weight.compare
  in
  if weights <> expected_weights then raise (Error "discrepancy in weights");
  let credentials = string_of_public_credentials credentials in
  let* () = write_file ~uuid "public_creds.json" [credentials] in
  se.se_public_creds_received <- true;
  Web_persist.set_draft_election uuid se

let get_draft_trustees se =
  match se.se_trustees with
  | `Basic x ->
     List.filter_map
       (fun t ->
         if t.st_id = "server" then
           None
         else
           Some {
               trustee_address = t.st_id;
               trustee_name = Option.value t.st_name ~default:"";
               trustee_token = Some t.st_token;
               trustee_state = Some (if t.st_public_key = "" then 0 else 1);
             }
       ) x.dbp_trustees
  | `Threshold x ->
     List.map
       (fun t ->
         {
           trustee_address = t.stt_id;
           trustee_name = Option.value t.stt_name ~default:"";
           trustee_token = Some t.stt_token;
           trustee_state = Some (Option.value t.stt_step ~default:0);
         }
       ) x.dtp_trustees

let check_address address =
  if not @@ is_email address then
    raise (Error (Printf.sprintf "invalid e-mail address: %s" address))

let ensure_none label x =
  if x <> None then
    raise (Error (Printf.sprintf "%s must not be set" label))

let generate_server_trustee se =
  let st_id = "server" and st_token = "" in
  let version = se.se_version in
  let module G = (val Group.of_string ~version se.se_group) in
  let module Trustees = (val Trustees.get_by_version version) in
  let module K = Trustees.MakeSimple (G) (LwtRandom) in
  let* private_key = K.generate () in
  let* public_key = K.prove private_key in
  let st_public_key = string_of_trustee_public_key G.write public_key in
  let st_private_key = Some private_key in
  let st_name = Some "server" in
  Lwt.return {st_id; st_token; st_public_key; st_private_key; st_name}

let post_draft_trustees uuid se t =
  let () = check_address t.trustee_address in
  let () = ensure_none "token" t.trustee_token in
  let () = ensure_none "state" t.trustee_state in
  match se.se_trustees with
  | `Basic x ->
     let* ts =
       let ts = x.dbp_trustees in
       if List.exists (fun x -> x.st_id = "server") ts then
         Lwt.return ts
       else
         let* server = generate_server_trustee se in
         Lwt.return (ts @ [server])
     in
     let () =
       if List.exists (fun x -> x.st_id = t.trustee_address) ts then
         raise (Error "address already used")
     in
     let* st_token = generate_token () in
     let t =
       {
         st_id = t.trustee_address;
         st_name = Some t.trustee_name;
         st_public_key = "";
         st_private_key = None;
         st_token;
       }
     in
     x.dbp_trustees <- ts @ [t];
     Web_persist.set_draft_election uuid se
  | `Threshold x ->
     let ts = x.dtp_trustees in
     let () =
       if List.exists (fun x -> x.stt_id = t.trustee_address) ts then
         raise (Error "address already used")
     in
     let* stt_token = generate_token () in
     let t =
       {
         stt_id = t.trustee_address;
         stt_name = Some t.trustee_name;
         stt_token; stt_step = None;
         stt_cert = None; stt_polynomial = None;
         stt_vinput = None; stt_voutput = None;
       }
     in
     x.dtp_trustees <- ts @ [t];
     Web_persist.set_draft_election uuid se

let rec filter_out_first f = function
  | [] -> false, []
  | x :: xs ->
     if f x then
       true, xs
     else (
       let touched, xs = filter_out_first f xs in
       touched, x :: xs
     )

let delete_draft_trustee uuid se trustee =
  match se.se_trustees with
  | `Basic x ->
     let ts = x.dbp_trustees in
     let touched, ts = filter_out_first (fun x -> x.st_id = trustee) ts in
     if touched then (
       x.dbp_trustees <- ts;
       let* () = Web_persist.set_draft_election uuid se in
       Lwt.return_true
     ) else (
       Lwt.return_false
     )
  | `Threshold x ->
     let ts = x.dtp_trustees in
     let touched, ts = filter_out_first (fun x -> x.stt_id = trustee) ts in
     if touched then (
       x.dtp_trustees <- ts;
       let* () = Web_persist.set_draft_election uuid se in
       Lwt.return_true
     ) else (
       Lwt.return_false
     )

let set_threshold uuid se threshold =
  match se.se_trustees with
  | `Basic _ ->
     Lwt.return @@ Stdlib.Error `NoTrustees
  | `Threshold x when x.dtp_trustees = [] ->
     Lwt.return @@ Stdlib.Error `NoTrustees
  | `Threshold x ->
     let ts = x.dtp_trustees in
     let maybe_threshold, step =
       if threshold = 0 then None, None else Some threshold, Some 1
     in
     if 0 <= threshold && threshold < List.length ts then (
       List.iter (fun t -> t.stt_step <- step) ts;
       x.dtp_threshold <- maybe_threshold;
       let* () = Web_persist.set_draft_election uuid se in
       Lwt.return @@ Ok ()
     ) else (
       Lwt.return @@ Stdlib.Error `OutOfBounds
     )

let get_draft_trustees_mode se =
  match se.se_trustees with
  | `Basic _ -> `Basic
  | `Threshold x -> `Threshold (Option.value x.dtp_threshold ~default:0)

let put_draft_trustees_mode uuid se mode =
  match get_draft_trustees_mode se, mode with
  | a, b when a = b -> Lwt.return_unit
  | _, `Basic ->
     se.se_trustees <- `Basic {dbp_trustees = []};
     Web_persist.set_draft_election uuid se
  | `Basic, `Threshold 0 ->
     let dtp =
       {
         dtp_threshold = None;
         dtp_trustees = [];
         dtp_parameters = None;
         dtp_error = None;
       }
     in
     se.se_trustees <- `Threshold dtp;
     Web_persist.set_draft_election uuid se
  | `Threshold _, `Threshold threshold ->
     begin
       let* x = set_threshold uuid se threshold in
       match x with
       | Ok () -> Lwt.return_unit
       | Error `NoTrustees -> Lwt.fail (Error "no trustees")
       | Error `OutOfBounds -> Lwt.fail (Error "threshold out of bounds")
     end
  | _, _ -> Lwt.fail (Error "change not allowed")

let get_draft_status uuid se =
  let* status_private_credentials_downloaded =
    if se.se_metadata.e_cred_authority = Some "server" then (
      let* b = file_exists (uuid /// "private_creds.downloaded") in
      Lwt.return_some b
    ) else Lwt.return_none
  in
  Lwt.return {
      status_num_voters = List.length se.se_voters;
      status_passwords_ready =
        begin
          match se.se_metadata.e_auth_config with
          | Some [{auth_system = "password"; _}] ->
             Some (List.for_all (fun v -> v.sv_password <> None) se.se_voters)
          | _ -> None
        end;
      status_credentials_ready = se.se_public_creds_received;
      status_private_credentials_downloaded;
      status_trustees_ready =
        begin
          match se.se_trustees with
          | `Basic x ->
             List.for_all (fun t -> t.st_public_key <> "") x.dbp_trustees
          | `Threshold x ->
             List.for_all (fun t -> t.stt_step = Some 7) x.dtp_trustees
        end;
      status_nh_and_weights_compatible =
        begin
          let has_weights =
            List.exists
              (fun x ->
                let _, _, weight = split_identity_opt x.sv_id in
                weight <> None
              ) se.se_voters
          in
          let has_nh =
            Array.exists
              (function
               | Belenios_core.Question.NonHomomorphic _ -> true
               | _ -> false
              ) se.se_questions.t_questions
          in
          not (has_weights && has_nh)
        end;
    }

let set_downloaded uuid =
  write_file ~uuid "private_creds.downloaded" []

let dump_passwords uuid db =
  List.map (fun line -> String.concat "," line) db |>
    write_file ~uuid "passwords.csv"

let validate_election uuid se =
  let* s = get_draft_status uuid se in
  let version = se.se_version in
  let uuid_s = raw_string_of_uuid uuid in
  (* convenience tests *)
  let () =
    if se.se_questions.t_name = "" then
      raise (Error "no title");
    if se.se_questions.t_questions = [||] then
      raise (Error "no questions");
    begin
      match se.se_administrator with
      | None | Some "" -> raise (Error "no administrator")
      | _ -> ()
    end;
    begin
      match se.se_metadata.e_cred_authority with
      | None | Some "" -> raise (Error "no credential authority")
      | _ -> ()
    end
  in
  (* check status *)
  let () =
    if s.status_num_voters = 0 then raise (Error "no voters");
    begin
      match s.status_passwords_ready with
      | Some false -> raise (Error "some passwords are missing")
      | Some true | None -> ()
    end;
    if not s.status_credentials_ready then
      raise (Error "public credentials are missing");
    if not s.status_trustees_ready then
      raise (Error "trustees are not ready");
    if not s.status_nh_and_weights_compatible then
      raise (Error "weights are incompatible with NH questions")
  in
  (* trustees *)
  let group = Group.of_string ~version se.se_group in
  let module G = (val group : GROUP) in
  let module Trustees = (val Trustees.get_by_version version) in
  let module K = Trustees.MakeCombinator (G) in
  let module KG = Trustees.MakeSimple (G) (LwtRandom) in
  let* trustee_names, trustees, private_keys =
    match se.se_trustees with
    | `Basic x ->
       let ts = x.dbp_trustees in
       let* trustee_names, trustees, private_key =
         match ts with
         | [] ->
            let* private_key = KG.generate () in
            let* public_key = KG.prove private_key in
            let public_key = { public_key with trustee_name = Some "server" } in
            Lwt.return (["server"], [`Single public_key], `KEY private_key)
         | _ :: _ ->
            let private_key =
              List.fold_left (fun accu {st_private_key; _} ->
                  match st_private_key with
                  | Some x -> x :: accu
                  | None -> accu
                ) [] ts
            in
            let private_key = match private_key with
              | [x] -> `KEY x
              | _ -> raise (Error "not a single private key")
            in
            Lwt.return
              begin
                (List.map (fun {st_id; _} -> st_id) ts),
                (List.map
                   (fun {st_public_key; st_name; _} ->
                     let pk = trustee_public_key_of_string G.read st_public_key in
                     let pk = { pk with trustee_name = st_name } in
                     `Single pk
                   ) ts),
                private_key
              end
       in
       Lwt.return (trustee_names, trustees, private_key)
    | `Threshold x ->
       let ts = x.dtp_trustees in
       match x.dtp_parameters with
       | None -> raise (Error "key establishment not finished")
       | Some tp ->
          let tp = threshold_parameters_of_string G.read tp in
          let named =
            let open Belenios_core.Serializable_j in
            List.combine (Array.to_list tp.t_verification_keys) ts
            |> List.map (fun (k, t) -> { k with trustee_name = t.stt_name })
            |> Array.of_list
          in
          let tp = { tp with t_verification_keys = named } in
          let trustee_names = List.map (fun {stt_id; _} -> stt_id) ts in
          let private_keys =
            List.map (fun {stt_voutput; _} ->
                match stt_voutput with
                | Some v ->
                   let voutput = voutput_of_string G.read v in
                   voutput.vo_private_key
                | None -> raise (Error "inconsistent state")
              ) ts
          in
          let* server_private_key = KG.generate () in
          let* server_public_key = KG.prove server_private_key in
          let server_public_key = { server_public_key with trustee_name = Some "server" } in
          Lwt.return
            begin
              "server" :: trustee_names,
              [`Single server_public_key; `Pedersen tp],
              `KEYS (server_private_key, private_keys)
            end
  in
  let y = K.combine_keys trustees in
  (* election parameters *)
  let metadata =
    {
      se.se_metadata with
      e_trustees = Some trustee_names;
      e_owners = se.se_owners;
    }
  in
  let template = se.se_questions in
  let params =
    {
      e_version = se.se_version;
      e_description = template.t_description;
      e_name = template.t_name;
      e_questions = template.t_questions;
      e_uuid = uuid;
      e_administrator = se.se_administrator;
      e_credential_authority = metadata.e_cred_authority;
    }
  in
  let raw_election =
    let public_key = G.to_string y in
    Election.make_raw_election params ~group:se.se_group ~public_key
  in
  (* write election files to disk *)
  let dir = !!uuid_s in
  let create_file fname what xs =
    Lwt_io.with_file
      ~flags:(Unix.([O_WRONLY; O_NONBLOCK; O_CREAT; O_TRUNC]))
      ~perm:0o600 ~mode:Lwt_io.Output (dir // fname)
      (fun oc ->
        Lwt_list.iter_s
          (fun v ->
            let* () = Lwt_io.write oc (what v) in
            Lwt_io.write oc "\n") xs)
  in
  let open Belenios_core.Serializable_j in
  let* () = create_file "voters.txt" (fun x -> x.sv_id) se.se_voters in
  let* () = create_file "metadata.json" string_of_metadata [metadata] in
  (* initialize credentials *)
  let* public_creds, public_creds_file =
    let fname = uuid /// "public_creds.json" in
    let* file = read_file_single_line fname in
    match file with
    | Some x ->
       let x = public_credentials_of_string x in
       let* () = Web_persist.init_credential_mapping uuid x in
       Lwt.return (x, fname)
    | None -> Lwt.fail @@ Failure "no public credentials"
  in
  (* initialize events *)
  let* () =
    let raw_trustees = string_of_trustees G.write trustees in
    let raw_public_creds = string_of_public_credentials public_creds in
    let setup_election = Hash.hash_string raw_election in
    let setup_trustees = Hash.hash_string raw_trustees in
    let setup_credentials = Hash.hash_string raw_public_creds in
    let setup_data =
      {
        setup_election;
        setup_trustees;
        setup_credentials;
      }
    in
    let setup_data_s = string_of_setup_data setup_data in
    Web_events.append ~lock:false ~uuid
      [
        Data raw_election;
        Data raw_trustees;
        Data raw_public_creds;
        Data setup_data_s;
        Event (`Setup, Some (Hash.hash_string setup_data_s));
      ]
  in
  (* create file with private keys, if any *)
  let* () =
    match private_keys with
    | `KEY x -> create_file "private_key.json" string_of_number [x]
    | `KEYS (x, y) ->
       let* () = create_file "private_key.json" string_of_number [x] in
       create_file "private_keys.jsons" (fun x -> x) y
  in
  (* clean up draft *)
  let* () = cleanup_file (uuid /// "draft.json") in
  let* () = cleanup_file public_creds_file in
  (* clean up private credentials, if any *)
  let* () = cleanup_file (uuid /// "private_creds.txt") in
  let* () = cleanup_file (uuid /// "private_creds.downloaded") in
  (* write passwords *)
  let* () =
    match metadata.e_auth_config with
    | Some [{auth_system = "password"; _}] ->
       let db =
         List.filter_map (fun v ->
             let _, login, _ = split_identity v.sv_id in
             let& salt, hashed = v.sv_password in
             Some [login; salt; hashed]
           ) se.se_voters
       in
       if db <> [] then dump_passwords uuid db else Lwt.return_unit
    | _ -> Lwt.return_unit
  in
  (* finish *)
  let* () = Web_persist.set_election_state uuid `Open in
  let* dates = Web_persist.get_election_dates uuid in
  Web_persist.set_election_dates uuid {dates with e_finalization = Some (now ())}

let merge_voters a b f =
  let weights =
    List.fold_left
      (fun accu sv ->
        let _, login, weight = split_identity sv.sv_id in
        let login = String.lowercase_ascii login in
        SMap.add login weight accu
      ) SMap.empty a
  in
  let rec loop weights accu = function
    | [] -> Ok (List.rev accu, Weight.(SMap.fold (fun _ x y -> x + y) weights zero))
    | sv_id :: xs ->
       let _, login, weight = split_identity sv_id in
       let login = String.lowercase_ascii login in
       if SMap.mem login weights then
         Stdlib.Error sv_id
       else
         loop (SMap.add login weight weights) ({sv_id; sv_password = f sv_id} :: accu) xs
  in
  loop weights (List.rev a) b

let import_voters uuid se from =
  let* voters = Web_persist.get_voters from in
  let* passwords = Web_persist.get_passwords from in
  let get_password =
    match passwords with
    | None -> fun _ -> None
    | Some p ->
       fun sv_id ->
       let _, login, _ = split_identity sv_id in
       SMap.find_opt (String.lowercase_ascii login) p
  in
  match voters with
  | Some voters ->
     if se.se_public_creds_received then (
       Lwt.return @@ Stdlib.Error `Forbidden
     ) else (
       match merge_voters se.se_voters voters get_password with
       | Ok (voters, total_weight) ->
          let expanded = Weight.expand ~total:total_weight total_weight in
          if Z.compare expanded Weight.max_expanded_weight <= 0 then (
            se.se_voters <- voters;
            let* () = Web_persist.set_draft_election uuid se in
            Lwt.return @@ Ok ()
          ) else (
            Lwt.return @@ Stdlib.Error (`TotalWeightTooBig total_weight)
          )
       | Error x -> Lwt.return @@ Stdlib.Error (`Duplicate x)
     )
  | None -> Lwt.return @@ Stdlib.Error `NotFound

let import_trustees uuid se from metadata =
  let open Belenios_core.Serializable_j in
  match metadata.e_trustees with
  | None -> Lwt.return @@ Stdlib.Error `None
  | Some names ->
     let* trustees = Web_persist.get_trustees from in
     let version = se.se_version in
     let module G = (val Group.of_string ~version se.se_group : GROUP) in
     let module Trustees = (val Trustees.get_by_version version) in
     let module K = Trustees.MakeCombinator (G) in
     let trustees = trustees_of_string G.read trustees in
     if not (K.check trustees) then
       Lwt.return @@ Stdlib.Error `Invalid
     else
       let import_pedersen t names =
         let* privs = Web_persist.get_private_keys from in
         let* x =
           match privs with
           | Some privs ->
              let rec loop ts pubs privs accu =
                match ts, pubs, privs with
                | stt_id :: ts, vo_public_key :: pubs, vo_private_key :: privs ->
                   let stt_name = vo_public_key.trustee_name in
                   let* stt_token = generate_token () in
                   let stt_voutput = {vo_public_key; vo_private_key} in
                   let stt_voutput = Some (string_of_voutput G.write stt_voutput) in
                   let stt = {
                       stt_id; stt_token; stt_voutput;
                       stt_step = Some 7; stt_cert = None;
                       stt_polynomial = None; stt_vinput = None;
                       stt_name;
                     } in
                   loop ts pubs privs (stt :: accu)
                | [], [], [] -> Lwt.return @@ Ok (List.rev accu)
                | _, _, _ -> Lwt.return @@ Stdlib.Error `Inconsistent
              in loop names (Array.to_list t.t_verification_keys) privs []
           | None -> Lwt.return @@ Stdlib.Error `MissingPrivateKeys
         in
         match x with
         | Ok se_threshold_trustees ->
            let dtp =
              {
                dtp_threshold = Some t.t_threshold;
                dtp_trustees = se_threshold_trustees;
                dtp_parameters = Some (string_of_threshold_parameters G.write t);
                dtp_error = None;
              }
            in
            se.se_trustees <- `Threshold dtp;
            let* () = Web_persist.set_draft_election uuid se in
            Lwt.return @@ Ok `Threshold
         | Stdlib.Error _ as x -> Lwt.return x
       in
       match trustees with
       | [`Pedersen t] ->
          import_pedersen t names
       | [`Single x; `Pedersen t] when x.trustee_name = Some "server" ->
          import_pedersen t (List.tl names)
       | ts ->
          let@ ts = fun cont ->
            try
              ts
              |> List.map (function `Single x -> x | `Pedersen _ -> raise Exit)
              |> cont
            with
            | Exit -> Lwt.return @@ Stdlib.Error `Unsupported
          in
          let* ts =
            let module KG = Trustees.MakeSimple (G) (LwtRandom) in
            List.combine names ts
            |> Lwt_list.map_p
                 (fun (st_id, public_key) ->
                   let* st_token, st_private_key, st_public_key =
                     if st_id = "server" then (
                       let* private_key = KG.generate () in
                       let* public_key = KG.prove private_key in
                       let public_key = string_of_trustee_public_key G.write public_key in
                       Lwt.return ("", Some private_key, public_key)
                     ) else (
                       let* st_token = generate_token () in
                       let public_key = string_of_trustee_public_key G.write public_key in
                       Lwt.return (st_token, None, public_key)
                     )
                   in
                   let st_name = public_key.trustee_name in
                   Lwt.return {st_id; st_token; st_public_key; st_private_key; st_name})
          in
          se.se_trustees <- `Basic {dbp_trustees = ts};
          let* () = Web_persist.set_draft_election uuid se in
          Lwt.return @@ Ok `Basic

let check_owner account uuid cont =
  let* metadata = Web_persist.get_election_metadata uuid in
  if Accounts.check account metadata.e_owners then
    cont metadata
  else
    unauthorized

let post_draft_status uuid se = function
  | `SetDownloaded ->
     let* () = set_downloaded uuid in
     ok
  | `ValidateElection ->
     let* () = validate_election uuid se in
     ok

let dispatch_draft ~token ~ifmatch endpoint method_ body uuid se =
  match endpoint with
  | [] ->
     begin
       let@ who = with_administrator_or_credential_authority_or_trustee token se in
       let get () =
         let* x = api_of_draft se in
         Lwt.return @@ string_of_draft x
       in
       match method_, who with
       | `GET, _ -> handle_get get
       | `PUT, `Administrator account ->
          let@ () = handle_ifmatch ifmatch get in
          let@ draft = body.run draft_of_string in
          let@ () = handle_generic_error in
          let update_cache =
            draft.draft_questions.t_name <> se.se_questions.t_name
            || se.se_owners <> draft.draft_owners
          in
          let se = draft_of_api account se draft in
          let* () = Web_persist.set_draft_election uuid se in
          let* () =
            if update_cache then
              Web_persist.clear_elections_by_owner_cache ()
            else
              Lwt.return_unit
          in
          ok
       | `POST, `Administrator _ ->
          let@ () = handle_ifmatch ifmatch get in
          let@ x = body.run draft_request_of_string in
          let@ () = handle_generic_error in
          post_draft_status uuid se x
       | `DELETE, `Administrator _ ->
          let@ () = handle_ifmatch ifmatch get in
          let@ () = handle_generic_error in
          let* () = delete_draft uuid in
          ok
       | _ -> method_not_allowed
     end
  | ["voters"] ->
     begin
       let@ who = with_administrator_or_credential_authority token se in
       let get () =
         let x = get_draft_voters se in
         Lwt.return @@ string_of_voter_list x
       in
       match method_, who with
       | `GET, _ -> handle_get get
       | `PUT, `Administrator _ ->
          let@ () = handle_ifmatch ifmatch get in
          if se.se_public_creds_received then (
            forbidden
          ) else (
            let@ voters = body.run voter_list_of_string in
            let@ () = handle_generic_error in
            let* () = put_draft_voters uuid se voters in
            ok
          )
       | `POST, `Administrator account ->
          let@ () = handle_ifmatch ifmatch get in
          let@ request = body.run voters_request_of_string in
          let@ () = handle_generic_error in
          begin
            match request with
            | `Import from ->
               let@ _ = check_owner account from in
               let* x = import_voters uuid se from in
               match x with
               | Ok () -> ok
               | Stdlib.Error `Forbidden -> forbidden
               | Stdlib.Error `NotFound -> not_found
               | Stdlib.Error (`TotalWeightTooBig _) -> Lwt.fail (Error "total weight too big")
               | Stdlib.Error (`Duplicate x) -> Lwt.fail (Error ("duplicate: " ^ x))
          end
       | _ -> method_not_allowed
     end
  | ["passwords"] ->
     begin
       let@ _ = with_administrator token se in
       let get () =
         let x = get_draft_passwords se in
         Lwt.return @@ string_of_voter_list x
       in
       match method_ with
       | `GET -> handle_get get
       | `POST ->
          let@ () = handle_ifmatch ifmatch get in
          let@ voters = body.run voter_list_of_string in
          let@ () = handle_generic_error in
          let generate =
            let title = se.se_questions.t_name in
            let langs = get_languages se.se_metadata.e_languages in
            let show_weight =
              List.exists
                (fun id ->
                  let _, _, weight = split_identity_opt id.sv_id in
                  weight <> None
                ) se.se_voters
            in
            fun metadata id ->
            Mails_voter.generate_password_email metadata langs title uuid id show_weight
          in
          let* jobs = post_draft_passwords generate uuid se voters in
          let* () = Mails_voter.submit_bulk_emails jobs in
          ok
       | _ -> method_not_allowed
     end
  | ["credentials"] ->
     begin
       let@ who = with_administrator_or_credential_authority token se in
       let get () =
         let* x = get_draft_credentials who uuid se in
         Lwt.return @@ string_of_credentials x
       in
       match method_ with
       | `GET -> handle_get get
       | `POST ->
          let@ () = handle_ifmatch ifmatch get in
          if se.se_public_creds_received then (
            forbidden
          ) else (
            let@ x = body.run credential_list_of_string in
            match who, x with
            | `Administrator _, [] ->
               begin
                 let@ () = handle_generic_error in
                 let send = Mails_voter.generate_credential_email uuid se in
                 let* x = generate_credentials_on_server send uuid se in
                 match x with
                 | Ok jobs ->
                    let* () = Mails_voter.submit_bulk_emails jobs in
                    ok
                 | Error e -> Lwt.fail @@ exn_of_generate_credentials_on_server_error e
               end
            | `CredentialAuthority, credentials ->
               let@ () = handle_generic_error in
               let* () = submit_public_credentials uuid se credentials in
               ok
            | _ -> forbidden
          )
       | _ -> method_not_allowed
     end
  | ["trustees-mode"] ->
     begin
       let@ _ = with_administrator token se in
       let get () =
         let x = get_draft_trustees_mode se in
         Lwt.return @@ string_of_trustees_mode x
       in
       match method_ with
       | `GET -> handle_get get
       | `PUT ->
          let@ () = handle_ifmatch ifmatch get in
          let@ mode = body.run trustees_mode_of_string in
          let@ () = handle_generic_error in
          let* () = put_draft_trustees_mode uuid se mode in
          ok
       | _ -> method_not_allowed
     end
  | ["trustees-pedersen"] ->
     begin
       let@ trustee, dtp = with_threshold_trustee token se in
       let get () =
         let pedersen_certs =
           List.fold_left (fun accu x ->
               match x.stt_cert with
               | None -> accu
               | Some c -> c :: accu
             ) [] dtp.dtp_trustees
           |> List.rev |> Array.of_list
         in
         let r =
           {
             pedersen_threshold = Option.value ~default:0 dtp.dtp_threshold;
             pedersen_step = Option.value ~default:0 trustee.stt_step;
             pedersen_certs;
             pedersen_vinput = trustee.stt_vinput;
             pedersen_voutput = Option.map (voutput_of_string Yojson.Safe.read_json) trustee.stt_voutput;
           }
         in
         Lwt.return @@ string_of_pedersen Yojson.Safe.write_json r
       in
       match method_ with
       | `GET -> handle_get get
       | _ -> method_not_allowed
     end
  | ["trustees"] ->
     begin
       let@ account = with_administrator token se in
       let get () =
         let x = get_draft_trustees se in
         Lwt.return @@ string_of_trustees x
       in
       match method_ with
       | `GET -> handle_get get
       | `POST ->
          let@ () = handle_ifmatch ifmatch get in
          let@ request = body.run trustees_request_of_string in
          let@ () = handle_generic_error in
          begin
            match request with
            | `Add trustee ->
               let* () = post_draft_trustees uuid se trustee in
               ok
            | `Import from ->
               let@ metadata = check_owner account from in
               let* x = import_trustees uuid se from metadata in
               match x with
               | Ok _ -> ok
               | Stdlib.Error e ->
                  let msg =
                    match e with
                    | `None -> "none"
                    | `Invalid -> "invalid"
                    | `Inconsistent -> "inconsistent"
                    | `MissingPrivateKeys -> "missing private keys"
                    | `Unsupported -> "unsupported"
                  in
                  Lwt.fail (Error msg)
          end
       | _ -> method_not_allowed
     end
  | ["trustees"; trustee] ->
     begin
       let@ _ = with_administrator token se in
       match method_ with
       | `DELETE ->
          let@ () = handle_generic_error in
          let* x = delete_draft_trustee uuid se trustee in
          if x then ok else not_found
       | _ -> method_not_allowed
     end
  | ["status"] ->
     begin
       let@ _ = with_administrator token se in
       match method_ with
       | `GET ->
          let@ () = handle_generic_error in
          let* x = get_draft_status uuid se in
          Lwt.return (200, string_of_status x)
       | _ -> method_not_allowed
     end
  | _ -> not_found

let dispatch ~token ~ifmatch endpoint method_ body =
  match endpoint with
  | [] ->
     begin
       let@ token = Option.unwrap unauthorized token in
       let@ account = Option.unwrap unauthorized (lookup_token token) in
       let get () =
         let* elections = Web_persist.get_elections_by_owner account.account_id in
         let elections =
           List.fold_left
             (fun accu (kind, summary_uuid, date, summary_name) ->
               let summary_date = unixfloat_of_datetime date in
               let summary_kind = None in
               if kind = `Draft then
                 {summary_uuid; summary_name; summary_date; summary_kind} :: accu
               else
                 accu
             ) [] elections
         in
         Lwt.return @@ string_of_summary_list elections
       in
       match method_ with
       | `GET -> handle_get get
       | `POST ->
          let@ () = handle_ifmatch ifmatch get in
          let@ draft = body.run draft_of_string in
          let@ () = handle_generic_error in
          let* uuid = post_drafts account draft in
          begin
            match uuid with
            | Some uuid -> Lwt.return (200, string_of_uuid uuid)
            | None -> forbidden
          end
       | _ -> method_not_allowed
     end
  | uuid :: endpoint ->
     let@ uuid = Option.unwrap bad_request (Option.wrap uuid_of_raw_string uuid) in
     let* se = Web_persist.get_draft_election uuid in
     let@ se = Option.unwrap not_found se in
     dispatch_draft ~token ~ifmatch endpoint method_ body uuid se
