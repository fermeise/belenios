(**************************************************************************)
(*                                BELENIOS                                *)
(*                                                                        *)
(*  Copyright © 2012-2020 Inria                                           *)
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

open Lwt
open Belenios_platform
open Belenios
open Serializable_builtin_t
open Serializable_j
open Signatures
open Common
open Web_serializable_builtin_t
open Web_serializable_j
open Web_common
open Web_services
open Eliom_content.Html.F
open Eliom_content.Html.F.Form

let ( / ) = Filename.concat

(* TODO: these pages should be redesigned *)

let site_title = "Election Server"
let admin_background = " background: #FF9999;"

let unsafe_a uri text =
  Printf.ksprintf Unsafe.data "<a href=\"%s\">%s</a>" uri text

let static x =
  let service = Eliom_service.static_dir () in
  make_uri ~service ["static"; x]

let format_user ~site u =
  em [txt (if site then string_of_user u else u.user_name)]

let login_box ?cont () =
  let style = "float: right; text-align: right;" ^ admin_background in
  let%lwt user = Eliom_reference.get Web_state.site_user in
  let auth_systems = List.map (fun x -> x.auth_instance) !Web_config.site_auth_config in
  let cont = match cont with
    | None -> ContSiteHome
    | Some x -> x
  in
  let login service = Eliom_service.preapply ~service:site_login (Some service, cont) in
  let logout () = Eliom_service.preapply ~service:logout cont in
  let body =
    match user with
    | Some user ->
      [
        div [
          txt "Logged in as ";
          format_user ~site:true user;
          txt ".";
        ];
        div [
          a ~a:[a_id "logout"] ~service:(logout ()) [txt "Log out"] ();
          txt ".";
        ];
      ]
    | None ->
      [
        div [
          txt "Not logged in.";
        ];
        let auth_systems =
          List.map (fun name ->
              a ~a:[a_id ("login_" ^ name)]
                ~service:(login name) [txt name] ()
            ) auth_systems |> List.join (txt ", ")
        in
        div (
          [txt "Log in: ["] @ auth_systems @ [txt "]"]
        );
      ]
  in
  return (div ~a:[a_style style] body)

let belenios_url = Eliom_service.extern
  ~prefix:"http://www.belenios.org"
  ~path:[]
  ~meth:(Eliom_service.Get Eliom_parameter.unit)
  ()

let base ~title ?login_box ~content ?(footer = div []) ?uuid () =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let administer =
    match uuid with
    | None ->
       a ~service:admin [txt (s_ "Administer elections")] ()
    | Some uuid ->
       a ~service:election_admin ~a:[a_id ("election_admin_" ^ (raw_string_of_uuid uuid))] [txt (s_ "Administer this election")] uuid
  in
  let login_box = match login_box with
    | None ->
       div ~a:[a_style "float: right; padding: 10px;"] [
         img ~a:[a_height 70] ~alt:""
           ~src:(static "placeholder.png") ();
       ]
    | Some x -> x
  in
  let%lwt warning = match !Web_config.warning_file with
    | None -> return @@ txt ""
    | Some f -> match%lwt read_file f with
                | None -> return @@ txt ""
                | Some x -> return @@ Unsafe.data (String.concat "\n" x)
  in
  Lwt.return (html ~a:[a_dir `Ltr; a_xml_lang lang]
    (head (Eliom_content.Html.F.title (txt title)) [
      script (txt "window.onbeforeunload = function () {};");
      link ~rel:[`Stylesheet] ~href:(static "site.css") ();
    ])
    (body [
      div ~a:[a_id "wrapper"] [
      div ~a:[a_id "header"] [
        div [
          div ~a:[a_style "float: left; padding: 10px;"] [
            a ~service:home [
              img ~alt:(s_ "Election server") ~a:[a_height 70]
                ~src:(static "logo.png") ();
            ] ();
          ];
          login_box;
          h1 ~a:[a_style "text-align: center; padding: 20px;"] [txt title];
          div ~a:[a_style "clear: both;"] [];
        ];
      ];
      warning;
      div ~a:[a_id "main"] content;
      div ~a:[a_id "footer"; a_style "text-align: center;" ] [
        div ~a:[a_id "bottom"] [
          footer;
          txt (s_ "Powered by ");
          a ~service:belenios_url [txt "Belenios"] ();
          Belenios_version.(
            Printf.ksprintf txt " %s (%s). " version build
          );
          a ~service:source_code [txt (s_ "Get the source code")] ();
          txt ". ";
          unsafe_a !Web_config.gdpr_uri (s_ "Privacy policy");
          txt ". ";
          administer;
          txt ".";
        ]
      ]]
     ]))

let privacy_notice cont =
  let title = site_title ^ " — Personal data processing notice" in
  let service = Eliom_service.preapply ~service:privacy_notice_accept cont in
  let content =
    [
      div [
          txt "To use this site, you must accept our ";
          unsafe_a !Web_config.gdpr_uri "personal data policy";
          txt ".";
        ];
      post_form ~service
        (fun () ->
          [
            div [
                input ~input_type:`Submit ~value:"Accept" string;
              ];
          ]
        ) ();
    ]
  in
  base ~title ~content ()

let format_election (uuid, name) =
  li [
    a ~service:election_admin ~a:[a_id ("election_admin_" ^ (raw_string_of_uuid uuid))] [txt name] uuid;
  ]

let format_draft_election (uuid, name) =
  li [
    a ~service:election_draft ~a:[a_id ("election_draft_" ^ (raw_string_of_uuid uuid))] [txt name] uuid;
  ]

let admin ~elections () =
  let title = site_title ^ " — Administration" in
  match elections with
  | None ->
     let contact = match !Web_config.contact_uri with
       | None -> txt ""
       | Some uri ->
          div [
              txt "If you do not have any account, you may ";
              unsafe_a uri "contact us";
              txt ".";
            ]
     in
     let content = [
       div [
         txt "To administer an election, you need to log in using one";
         txt " of the authentication methods available in the upper";
         txt " right corner of this page.";
         contact;
       ]
     ] in
     let%lwt login_box = login_box ~cont:ContSiteAdmin () in
     base ~title ~login_box ~content ()
  | Some (draft, elections, tallied, archived) ->
    let draft =
      match draft with
      | [] -> p [txt "You own no such elections!"]
      | _ -> ul @@ List.map format_draft_election draft
    in
    let elections =
      match elections with
      | [] -> p [txt "You own no such elections!"]
      | _ -> ul @@ List.map format_election elections
    in
    let tallied =
      match tallied with
      | [] -> p [txt "You own no such elections!"]
      | _ -> ul @@ List.map format_election tallied
    in
    let archived =
      match archived with
      | [] -> p [txt "You own no such elections!"]
      | _ -> ul @@ List.map format_election archived
    in
    let content = [
      div [
        div [
          a ~service:election_draft_pre [
            txt "Prepare a new election";
          ] ();
        ];
        div [br ()];
        h2 [txt "Elections being prepared"];
        draft;
        div [br ()];
        h2 [txt "Elections you can administer"];
        elections;
        div [br ()];
        h2 [txt "Tallied elections"];
        tallied;
        div [br ()];
        h2 [txt "Archived elections"];
        archived;
      ];
    ] in
    let%lwt login_box = login_box () in
    base ~title ~login_box ~content ()

let make_button ~service ?hash ?style ~disabled contents =
  let uri = Eliom_uri.make_string_uri ~service () in
  let uri = match hash with
    | None -> uri
    | Some x -> uri ^ "#" ^ x
  in
  let style =
    match style with
    | None -> ""
    | Some x -> Printf.sprintf " style=\"%s\"" x
  in
  Printf.ksprintf Unsafe.data (* FIXME: unsafe *)
    "<button onclick=\"location.href='%s';\"%s%s>%s</button>"
    uri style (if disabled then " disabled" else "")
    contents

let make_a_with_hash ~service ?hash ?style contents =
  let uri = Eliom_uri.make_string_uri ~service () in
  let uri = match hash with
    | None -> uri
    | Some x -> uri ^ "#" ^ x
  in
  let style =
    match style with
    | None -> ""
    | Some x -> Printf.sprintf " style=\"%s\"" x
  in
  Printf.ksprintf Unsafe.data (* FIXME: unsafe *)
    "<a href=\"%s\"%s>%s</a>"
    uri style contents

let a_mailto ~dest ~subject ~body contents =
  let uri = Printf.sprintf "mailto:%s?subject=%s&amp;body=%s" dest
    (Netencoding.Url.encode ~plus:false subject)
    (Netencoding.Url.encode ~plus:false body)
  in
  Printf.ksprintf Unsafe.data "<a href=\"%s\">%s</a>"
    uri contents

let new_election_failure reason () =
  let title = "Create new election" in
  let reason =
    match reason with
    | `Exists -> txt "An election with the same UUID already exists."
    | `Exception e -> txt @@ Printexc.to_string e
  in
  let content = [
    div [
      p [txt "The creation failed."];
      p [reason];
    ]
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let generic_page ~title ?service message () =
  let proceed = match service with
    | None -> txt ""
    | Some service ->
       div [
         a ~service ~a:[a_id "generic_proceed_link"] [txt "Proceed"] ();
       ]
  in
  let content = [
    p [txt message];
    proceed;
  ] in
  base ~title ~content ()

let election_draft_pre () =
  let title = "Prepare a new election" in
  let cred_info = Eliom_service.extern
    ~prefix:"http://www.belenios.org"
    ~path:["setup.html"]
    ~meth:(Eliom_service.Get Eliom_parameter.unit)
    ()
  in
  let form =
    post_form ~service:election_draft_new
      (fun (credmgmt, (auth, cas_server)) ->
        [
          fieldset
            ~legend:(legend [
              txt "Credential management (";
              a ~service:cred_info [txt "more info"] ();
              txt ")";
            ])
            [
              div [
                radio ~checked:true ~name:credmgmt ~value:"auto" string;
                txt " Automatic (degraded mode - credentials will be handled by the server)";
              ];
              div [
                radio ~name:credmgmt ~value:"manual" string;
                txt " Manual (safe mode - a third party will handle the credentials)";
              ];
            ];
          fieldset
            ~legend:(legend [txt "Authentication"])
            [
              div [
                radio ~checked:true ~name:auth ~value:"password" string;
                txt " Password (passwords will be emailed to voters)";
              ];
              div [
                radio ~name:auth ~value:"cas" string;
                txt " CAS (external authentication server), server address: ";
                input ~input_type:`Text ~name:cas_server string;
                txt " (for example: https://cas.inria.fr/cas)";
              ];
            ];
          div [
            input ~input_type:`Submit ~value:"Proceed" string;
          ];
        ]
      ) ()
  in
  let content = [
    form
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let preview_booth uuid =
  let hash = Netencoding.Url.mk_url_encoded_parameters ["uuid", raw_string_of_uuid uuid] in
  let service =
    Eliom_uri.make_string_uri
      ~service:election_vote ~absolute:true () |> rewrite_prefix
  in
  span [
      unsafe_a (service ^ "#" ^ hash) "Preview booth";
      txt " (you can use any credential such as HsqB3C3y62Ekq4D)."
    ]

let election_draft uuid se () =
  let title = "Preparation of election " ^ se.se_questions.t_name in
  let form_languages =
    post_form ~service:election_draft_languages
      (fun languages ->
        [
          div [
              txt "Languages: ";
              input ~name:languages ~input_type:`Text
                ~value:(string_of_languages se.se_metadata.e_languages) string;
              txt " (Available languages: ";
              txt (string_of_languages (Some available_languages));
              txt ")";
            ];
          div [
              txt "This is a space-separated list of languages that will be used in emails sent by the server.";
            ];
          div [
              input ~input_type:`Submit ~value:"Save changes" string;
            ];
        ]) uuid
  in
  let div_languages =
    div [
        h2 [txt "Languages"];
        form_languages;
      ]
  in
  let form_description =
    post_form ~service:election_draft_description
      ~a:[a_id "name_and_description_form"]
      (fun (name, description) ->
        [
          div [
            txt "Name of the election: ";
            input ~name:name
              ~input_type:`Text ~value:se.se_questions.t_name string;
          ];
          div [
            div [txt "Description of the election: "];
            div [
              textarea ~name:description ~a:[a_cols 80]
                ~value:se.se_questions.t_description ();
            ];
          ];
          div [
            input ~input_type:`Submit ~value:"Save changes" string;
          ];
        ]
      ) uuid
  in
  let div_description =
    div [
      h2 [txt "Name and description of the election"];
      form_description;
    ]
  in
  let form_admin_name =
    post_form ~service:election_draft_admin_name ~a:[a_id "form_admin_name"]
      (fun name ->
        [
          div [
              txt "Public name of the administrator: ";
              let value =
                match se.se_administrator with
                | Some x -> x
                | None -> ""
              in
              input ~name ~input_type:`Text ~value string;
            ];
          div [
              txt "This name will be published on the election result page.";
            ];
          div [
              input ~input_type:`Submit ~value:"Save changes" string;
            ];
        ]) uuid
  in
  let div_admin_name =
    div [
        h2 [txt "Public name of the administrator"];
        form_admin_name;
      ]
  in
  let form_contact =
    post_form ~service:election_draft_contact ~a:[a_id "form_contact"]
      (fun contact ->
        [
          div [
              txt "Contact: ";
              let value =
                match se.se_metadata.e_contact with
                | Some x -> x
                | None -> default_contact
              in
              input ~name:contact ~input_type:`Text ~value string;
            ];
          div [
              txt "This contact will be added to emails sent to the voters.";
            ];
          div [
              input ~input_type:`Submit ~value:"Save changes" string;
            ];
        ]) uuid
  in
  let div_contact =
    div [
        h2 [txt "Contact"];
        form_contact;
      ]
  in
  let auth = match se.se_metadata.e_auth_config with
    | Some [{auth_system = "password"; _}] -> `Password
    | Some [{auth_system = "dummy"; _}] -> `Dummy
    | Some [{auth_system = "cas"; auth_config = ["server", server]; _}] -> `CAS server
    | _ -> failwith "unknown authentication scheme in election_draft"
  in
  let div_auth =
    div [
      h2 [txt "Authentication"];
      match auth with
      | `Password ->
         div [
           txt "Authentication scheme: password";
           if List.for_all (fun v -> v.sv_password <> None) se.se_voters then
             div [txt "All passwords have been sent!"]
           else
             post_form ~service:election_draft_auth_genpwd
               (fun () ->
                 [input ~input_type:`Submit ~value:"Generate and mail missing passwords" string]
               ) uuid;
         ]
      | `Dummy ->
         div [
           txt "Authentication scheme: dummy"
         ]
      | `CAS server ->
         div [
           txt "Authentication scheme: CAS with server ";
           txt server;
         ]
    ]
  in
  let div_questions =
    div [
      h2 [
        a ~a:[a_id "edit_questions"] ~service:election_draft_questions
          [txt "Edit questions"]
          uuid;
      ];
      preview_booth uuid;
    ]
  in
  let div_voters =
    div [
      h2 [
        a ~a:[a_id "edit_voters"] ~service:election_draft_voters
          [txt "Edit voters"]
          uuid
      ];
      div [
        txt @@ string_of_int @@ List.length se.se_voters;
        txt " voter(s) registered";
      ];
    ]
  in
  let div_trustees =
    div [
      h2 [txt "Trustees"];
      div [
          txt "By default, the election server manages the keys of the election (degraded privacy mode). ";
          txt "For real elections, the key must be shared among independent trustees. Click ";
          a ~service:election_draft_trustees [txt "here"] uuid;
          txt " to set up the election key.";
        ];
    ]
  in
  let cred_auth_is_server = se.se_metadata.e_cred_authority = Some "server" in
  let div_credentials =
    div [
      h2 [txt "Credentials"];
      if se.se_public_creds_received then (
        let div_private_creds =
          if cred_auth_is_server then
            div [
                a ~service:election_draft_credentials_get
                  [txt "Download private credentials"] uuid
              ]
          else txt ""
        in
        let div_edit_credential_authority_name =
          if cred_auth_is_server then
            txt ""
          else
            div [
                a ~service:election_draft_credential_authority [
                    txt "Edit credential authority name";
                  ] uuid;
              ]
        in
        div [
          div [txt "Credentials have already been generated!"];
          div_edit_credential_authority_name;
          div_private_creds;
        ]
      ) else (
        div [
          txt "Warning: this will freeze the voter list!";
          if cred_auth_is_server then (
            post_form ~service:election_draft_credentials_server
              (fun () ->
                [input ~input_type:`Submit ~value:"Generate on server" string]
              ) uuid
          ) else (
            div [
              a ~service:election_draft_credential_authority [txt "Credential management"] uuid;
            ]
          );
        ]
      )
    ]
  in
  let link_confirm = div [
    h2 [txt "Validate creation"];
    a ~service:election_draft_confirm [txt "Create election"] uuid;
  ] in
  let form_destroy =
    let t = Option.get se.se_creation_date default_creation_date in
    let t = datetime_add t (day days_to_delete) in
    post_form
      ~service:election_draft_destroy
      (fun () ->
        [
          div [
              h2 [txt "Destroy election"];
              div [
                  txt "Note: this election will be automatically destroyed after ";
                  txt (format_datetime t);
                  txt ".";
                ];
              input ~input_type:`Submit ~value:"Destroy election" string;
            ]
        ]
      ) uuid
  in
  let content = [
    div_description;
    hr ();
    div_admin_name;
    hr ();
    div_languages;
    hr ();
    div_contact;
    hr ();
    div_questions;
    hr ();
    div_voters;
    hr ();
    div_credentials;
    hr ();
    div_auth;
    hr ();
    div_trustees;
    hr ();
    link_confirm;
    hr ();
    form_destroy;
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let mail_trustee_generation_basic : ('a, 'b, 'c, 'd, 'e, 'f) format6 =
  "Dear trustee,

You will find below the link to generate your private decryption key,
used to tally the election.

  %s

Here are the instructions:
1. Click on the link.
2. Click on \"Generate a new key pair\".
3. Download your private key. Make sure you SAVE IT properly otherwise
   it will not be possible to tally and the election will be canceled.
4. Save the fingerprint of your verification key. Once the election
   is open, you must check that it is present in the set of verification
   keys published by the server.
5. Click on \"Submit\" to send your verification key, used to encrypt
   the votes.

Regarding your private key, it is crucial you save it (otherwise the
election will be canceled) and store it securely (if your private key
is known together with the private keys of the other trustees, then
vote privacy is no longer guaranteed). We suggest two options:
1. you may store the key on a USB stick and store it in a safe;
2. or you may simply print it and store it in a safe.
Of course, more cryptographic solutions are welcome as well.

Thank you for your help,

-- \nThe election administrator."

let mail_trustee_generation_threshold : ('a, 'b, 'c, 'd, 'e, 'f) format6 =
  "Dear trustee,

You will find below the link to generate your private decryption key,
used to tally the election.

  %s

Follow the instructions. There will be 3 steps. All trustees must have
completed one step before you can proceed to the next one.

Don't forget to save:
1. your private key. Make sure you SAVE IT properly otherwise you will
   not be able to participate to the tally and the election may be
   canceled;
3. the fingerprint of your public key;
4. the fingerprint of your verification key.

Once the election is open, you must check that the fingerprints of
your two keys are present in the set of keys published by the server.

Regarding your private key, it is crucial you save it (otherwise the
election may be canceled) and store it securely (if your private key
is known together with the private keys of the other trustees, then
vote privacy is no longer guaranteed). We suggest two options:
1. you may store the key on a USB stick and store it in a safe;
2. or you may simply print it and store it in a safe.
Of course, more cryptographic solutions are welcome as well.

Thank you for your help,

-- \nThe election administrator."

let election_draft_trustees ?token uuid se () =
  let title = "Trustees for election " ^ se.se_questions.t_name in
  let form_trustees_add =
    post_form
      ~service:election_draft_trustee_add
      (fun (n_id, n_comment) ->
        [
          txt "Trustee's e-mail address: ";
          input ~input_type:`Text ~name:n_id string;
          txt ", public name: ";
          input ~input_type:`Text ~name:n_comment string;
          input ~input_type:`Submit ~value:"Add" string;
        ]
      ) uuid
  in
  let mk_form_trustee_del value =
    post_form
      ~service:election_draft_trustee_del
      (fun name ->
        [
          input ~input_type:`Hidden ~name ~value int;
          input ~input_type:`Submit ~value:"Remove" string;
        ]) uuid
  in
  let trustees = match se.se_public_keys with
    | [] -> txt ""
    | ts ->
       let ts =
         List.mapi
           (fun i t ->
             let this_line =
               match token with
               | Some x when x = t.st_token -> true
               | _ -> false
             in
             let first_line =
               tr [
                   td [
                       txt t.st_id;
                     ];
                   td [
                       match t.st_name with
                       | None -> txt "(not available)"
                       | Some x -> txt x
                     ];
                   td [
                       if t.st_token <> "" then (
                         let uri = rewrite_prefix @@ Eliom_uri.make_string_uri
                                                       ~absolute:true ~service:election_draft_trustee (uuid, t.st_token)
                         in
                         let body = Printf.sprintf mail_trustee_generation_basic uri in
                         let subject = "Link to generate the decryption key" in
                         a_mailto ~dest:t.st_id ~subject ~body "Mail"
                       ) else (
                         txt "(server)"
                       )
                     ];
                   td [
                       if t.st_token <> "" then (
                         if this_line then
                           a ~service:election_draft_trustees [txt "Hide link"] uuid
                         else
                           a ~service:election_draft_trustee [txt "Link"] (uuid, t.st_token);
                       ) else (
                         txt "(server)"
                       )
                     ];
                   td [
                       txt (if t.st_public_key = "" then "No" else "Yes");
                     ];
                   td [if t.st_id = "server" then txt "(cannot be removed)" else mk_form_trustee_del i];
                 ]
             in
             let second_line =
               if this_line then
                 [
                   tr
                     [
                       td ~a:[a_colspan 6]
                         [
                           txt "The link that must be sent to trustee ";
                           txt t.st_id;
                           txt " is:";
                           br ();
                           Eliom_uri.make_string_uri ~absolute:true
                             ~service:election_draft_trustee (uuid, t.st_token)
                           |> rewrite_prefix |> txt
                         ]
                     ]
                 ]
               else []
             in
             first_line :: second_line
           ) ts
       in
       table (
           tr [
               th [txt "Trustee"];
               th [txt "Public name"];
               th [txt "Mail"];
               th [txt "Link"];
               th [txt "Done?"];
               th [txt "Remove"];
             ] :: (List.flatten ts)
         )
  in
  let import_link = div [
                        a ~service:Web_services.election_draft_import_trustees
                          [txt "Import trustees from another election"] uuid
                      ]
  in
  let div_trustees =
    if se.se_threshold_trustees = None then
      div [
          trustees;
          (if se.se_public_keys <> [] then
             div [
                 txt "There is one link per trustee. Send each trustee her link.";
                 br ();
                 br ();
               ]
           else txt "");
          form_trustees_add;
        ]
    else txt ""
  in
  let div_content =
    div [
      div [
          txt "To set up the election key, you need to nominate trustees. Each trustee will create her own secret key. ";
          txt "To set up the election so that only a subset of trustees is needed, go to the ";
          a ~service:election_draft_threshold_trustees [txt "threshold mode"] uuid;
          txt ".";
        ];
      br ();
      div_trustees;
    ]
  in
  let back_link = div [
    a ~service:Web_services.election_draft
      [txt "Go back to election draft"] uuid;
  ] in
  let content = [
    div_content;
    import_link;
    back_link;
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let election_draft_threshold_trustees ?token uuid se () =
  let title = "Trustees for election " ^ se.se_questions.t_name in
  let show_add_remove = se.se_threshold = None in
  let form_trustees_add =
    if show_add_remove then
      post_form
        ~service:election_draft_threshold_trustee_add
        (fun (n_id, n_comment) ->
          [
            txt "Trustee's e-mail address: ";
            input ~input_type:`Text ~name:n_id string;
            txt ", public name: ";
            input ~input_type:`Text ~name:n_comment string;
            input ~input_type:`Submit ~value:"Add" string;
          ]
        ) uuid
    else txt ""
  in
  let mk_form_trustee_del value =
    post_form
      ~service:election_draft_threshold_trustee_del
      (fun name ->
        [
          input ~input_type:`Hidden ~name ~value int;
          input ~input_type:`Submit ~value:"Remove" string;
      ]) uuid
  in
  let trustees = match se.se_threshold_trustees with
    | None -> txt ""
    | Some ts ->
       let ts =
         List.mapi (fun i t ->
             let this_line =
               match token with
               | Some x when x = t.stt_token -> true
               | _ -> false
             in
             let state =
               match t.stt_step with
               | None -> "init"
               | Some 1 -> "1a"
               | Some 2 -> "1b"
               | Some 3 -> "2a"
               | Some 4 -> "2b"
               | Some 5 -> "3a"
               | Some 6 -> "3b"
               | Some 7 -> "done"
               | _ -> "unknown"
             in
             let first_line =
               tr (
                   [
                     td [
                         txt t.stt_id;
                       ];
                     td [
                         match t.stt_name with
                         | None -> txt "(not available)"
                         | Some x -> txt x
                       ];
                     td [
                         let uri = rewrite_prefix @@
                                     Eliom_uri.make_string_uri
                                       ~absolute:true ~service:election_draft_threshold_trustee (uuid, t.stt_token)
                         in
                         let body = Printf.sprintf mail_trustee_generation_threshold uri in
                         let subject = "Link to generate the decryption key" in
                         a_mailto ~dest:t.stt_id ~subject ~body "Mail"
                       ];
                     td [
                         if this_line then
                           a ~service:election_draft_threshold_trustees [txt "Hide link"] uuid
                         else
                           a ~service:election_draft_threshold_trustee [txt "Link"] (uuid, t.stt_token)
                       ];
                     td [
                         txt state;
                       ];
                   ] @ (if show_add_remove then [td [mk_form_trustee_del i]] else [])
                 )
             in
             let second_line =
               if this_line then
                 [
                   tr
                     [
                       td ~a:[a_colspan (if show_add_remove then 6 else 5)]
                         [
                           txt "The link that must be sent to trustee ";
                           txt t.stt_id;
                           txt " is:";
                           br ();
                           Eliom_uri.make_string_uri ~absolute:true
                             ~service:election_draft_threshold_trustee
                             (uuid, t.stt_token)
                           |> rewrite_prefix |> txt
                         ]
                     ]
                 ]
               else []
             in
             first_line :: second_line
           ) ts
       in
       div [
           table (
               tr (
                   [
                     th [txt "Trustee"];
                     th [txt "Public name"];
                     th [txt "Mail"];
                     th [txt "Link"];
                     th [txt "State"];
                   ] @ (if show_add_remove then [th [txt "Remove"]] else [])
                 ) :: (List.flatten ts)
             );
           div [
               txt "Meaning of states:";
               ul [
                   li [txt "init: administrator needs to set threshold"];
                   li [txt "1a: action needed from trustee: generate private key"];
                   li [txt "2a, 3a: action needed from trustee: enter private key"];
                   li [txt "1b, 2b, 3b: waiting for other trustees"];
                   li [txt "done: the key establishment protocol is finished"];
                 ];
             ];
           br ();
         ]
  in
  let form_threshold, form_reset =
    match se.se_threshold_trustees with
    | None -> txt "", txt ""
    | Some ts ->
       match se.se_threshold with
       | None ->
          post_form ~service:election_draft_threshold_set
            (fun name ->
              [
                txt "Threshold: ";
                input ~input_type:`Text ~name int;
                input ~input_type:`Submit ~value:"Set" string;
                txt " (the threshold must be smaller than the number of trustees)";
              ]
            ) uuid,
          txt ""
       | Some i ->
          div [
              txt (string_of_int i);
              txt " out of ";
              txt (string_of_int (List.length ts));
              txt " trustees will be needed to decrypt the result.";
            ],
          post_form ~service:election_draft_threshold_set
            (fun name ->
              [
                input ~input_type:`Hidden ~name ~value:0 int;
                input ~input_type:`Submit ~value:"Reset threshold" string;
              ]
            ) uuid
  in
  let maybe_error =
    match se.se_threshold_error with
    | None -> txt ""
    | Some e -> div [b [txt "ERROR: "]; txt e; br (); br ()]
  in
  let div_content =
    div [
      div [txt "On this page, you can configure a group of trustees such that only a subset of them is needed to perform the decryption."];
      br ();
      form_threshold;
      br ();
      trustees;
      (if se.se_threshold_trustees <> None then
          div [
            txt "There is one link per trustee. Send each trustee her link.";
            br ();
            br ();
            maybe_error;
          ]
       else txt "");
      form_trustees_add;
      form_reset;
    ]
  in
  let back_link = div [
    a ~service:Web_services.election_draft
      [txt "Go back to election draft"] uuid;
  ] in
  let content = [
    div_content;
    br ();
    back_link;
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let election_draft_credential_authority uuid se () =
  let title = "Credentials for election " ^ se.se_questions.t_name in
  let public_name_form =
    post_form ~service:election_draft_set_credential_authority
      (fun name ->
        let value =
          match se.se_metadata.e_cred_authority with
          | Some x -> x
          | None -> ""
        in
        [
          txt "Public name of the credential authority: ";
          input ~input_type:`Text ~name ~value string;
          input ~input_type:`Submit ~value:"Set" string;
        ]
      ) uuid
  in
  let back =
    div [
        a ~service:Web_services.election_draft
          [txt "Back to election preparation page"] uuid;
      ]
  in
  let content = [
    back;
    public_name_form;
    div [
      txt "Please send the credential authority the following link:";
    ];
    ul [
      li [
        a
          ~a:[a_id "credential_authority_link"]
          ~service:election_draft_credentials
          [
            txt @@ rewrite_prefix @@ Eliom_uri.make_string_uri
              ~absolute:true
              ~service:election_draft_credentials
              (uuid, se.se_public_creds)
          ]
          (uuid, se.se_public_creds);
      ];
    ];
    div [
      txt "Note that this authority will have to send each credential to each voter herself.";
    ];
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let election_draft_credentials_done se () =
  let title = "Credentials for election " ^ se.se_questions.t_name in
  let content =
    [
      div [txt "Credentials have been received and checked!"];
      div [
          div [b [txt "Instructions"]];
          div [
              txt "Once the election is open, check that:";
              ol [
                  li [
                      txt "the number of voters is correct, and the fingerprint of the voter list matches what has been saved, for example with the following command:";
                      pre [txt "sha256sum voters.txt | xxd -p -r | base64 | tr -d \"=\""];
                      txt "(or ";
                      code [txt "shasum -a256"];
                      txt " instead of ";
                      code [txt "sha256sum"];
                      txt ");"
                    ];
                  li [
                      txt "the fingerprint of public credentials matches what has been saved, for example with the following command:";
                      pre [txt "sha256sum public_creds.txt | xxd -p -r | base64 | tr -d \"=\""];
                      txt "(or ";
                      code [txt "shasum -a256"];
                      txt " instead of ";
                      code [txt "sha256sum"];
                      txt ");"
                    ];
                  li [
                      txt "you can send again a private credential to its rightful owner in case of loss."
                    ];
                ];
            ];
          div [
              txt "Once the election is over, the file creds.txt must be destroyed.";
            ];
        ];
    ]
  in
  base ~title ~content ()

let election_draft_questions uuid se () =
  let title = "Questions for election " ^ se.se_questions.t_name in
  let form =
    let value = string_of_template se.se_questions in
    post_form
      ~service:election_draft_questions_post
      (fun name ->
       [
         div [txt "Questions:"];
         div [textarea ~a:[a_id "questions"; a_rows 5; a_cols 80] ~name ~value ()];
         div [input ~input_type:`Submit ~value:"Save changes" string]])
      uuid
  in
  let allow_nh =
    match get_suitable_group_kind se.se_questions with
    | `NH -> true
    | `H -> not (is_group_fixed se)
  in
  let hybrid_box =
    div ~a:[a_class ["hybrid_box"]]
      [
        div [txt "Alternative voting methods (warning, still experimental):"];
        div
          [
            txt "You may wish voters to rank candidates or give each candidate a score.";
            txt "This allows deciding the winner according to your favorite counting method ";
            txt "(e.g. Condorcet, STV, majority judgement).";
          ];
        div [txt "Note that:"];
        ol
          [
            li [txt "the after-the-vote procedure will require more steps;"];
            li
              [
                txt "you will be given the raw results (shuffled list of ballots) ";
                txt "and you will need to apply your counting method yourself."
              ];
          ];
        div
          [
            input ~a:[a_id "hybrid_mode"] ~input_type:`Checkbox string;
            txt "Tick the box to activate this mode.";
          ];
      ]
  in
  let interactivity =
    div
      ~a:[a_id "interactivity"]
      [
        script (Printf.ksprintf txt "var allow_nh = %b;" allow_nh);
        script ~a:[a_src (static "tool_js_questions.js")] (txt "");
        hybrid_box;
      ]
  in
  let preview = div [hr (); preview_booth uuid] in
  let content = [
    interactivity;
    form;
    preview;
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let election_draft_voters uuid se maxvoters () =
  let title = "Voters for election " ^ se.se_questions.t_name in
  let form =
    post_form
      ~service:election_draft_voters_add
      (fun name ->
        [
          div [textarea ~a:[a_rows 20; a_cols 50] ~name ()];
          div [input ~input_type:`Submit ~value:"Add" string]])
      uuid
  in
  let mk_remove_button id =
    post_form
      ~service:election_draft_voters_remove
      (fun name ->
        [
          input ~input_type:`Hidden ~name ~value:id string;
          input ~input_type:`Submit ~value:"Remove" string;
        ]
      ) uuid
  in
  let has_passwords = match se.se_metadata.e_auth_config with
    | Some [{auth_system = "password"; _}] -> true
    | _ -> false
  in
  let mk_regen_passwd value =
    post_form ~service:election_draft_voters_passwd
      ~a:[a_style "display: inline;"]
      (fun name ->
        [
          input ~input_type:`Hidden ~name ~value string;
          input ~input_type:`Submit ~value:"Send again" string;
        ]
      ) uuid
  in
  let format_password_cell x = match x.sv_password with
    | Some _ -> [txt "Yes "; mk_regen_passwd x.sv_id]
    | None -> [txt "No"]
  in
  let voters =
    List.map (fun v ->
      tr (
        [td [txt v.sv_id]] @
        (if has_passwords then [td (format_password_cell v)] else []) @
        (if se.se_public_creds_received then [] else [td [mk_remove_button v.sv_id]])
      )
    ) se.se_voters
  in
  let form_passwords =
    if has_passwords then
      post_form ~service:election_draft_auth_genpwd
        (fun () ->
          [input ~input_type:`Submit ~value:"Generate and mail missing passwords" string]
        ) uuid
    else txt ""
  in
  let voters =
    match voters with
    | [] -> div [txt "No voters"]
    | _ :: _ ->
       div [
         form_passwords;
         br ();
         table
           (tr (
             [th [txt "Identity"]] @
               (if has_passwords then [th [txt "Password sent?"]] else []) @
               (if se.se_public_creds_received then [] else [th [txt "Remove"]])
            ) :: voters)
       ]
  in
  let back = div [
    a ~service:Web_services.election_draft [txt "Return to draft page"] uuid;
  ] in
  let div_add =
    if se.se_public_creds_received then
      txt ""
    else
      div [
        div [
            txt "Please enter the identities of voters to add, one per line (max ";
            txt (string_of_int maxvoters);
            txt ").";
            br ();
            b [txt "Warning:"];
            txt " you have to make sure that these email addresses are valid. You won't be able to change the email addresses once the election is set up. Voters with invalid email addresses won't be able to vote.";
          ];
        form;
        div [
          b [txt "Note:"];
          txt " An identity is either an e-mail address, or \"address,login\",";
          txt " where \"address\" is an e-mail address and \"login\" the";
          txt " associated login for authentication.";
        ];
      ]
  in
  let div_import = div [
    a ~service:election_draft_import
      [txt "Import voters from another election"]
      uuid
  ] in
  let content = [
    back;
    div_import;
    br ();
    voters;
    div_add;
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let unsafe_textarea ?rows ?cols id contents =
  let rows = match rows with
    | None -> ""
    | Some i -> Printf.sprintf " rows=\"%d\"" i
  in
  let cols = match cols with
    | None -> ""
    | Some i -> Printf.sprintf " cols=\"%d\"" i
  in
  Printf.ksprintf Unsafe.data
    "<textarea id=\"%s\"%s%s>%s</textarea>"
    id rows cols contents

let election_draft_credentials token uuid se () =
  let title = "Credentials for election " ^ se.se_questions.t_name in
  let div_link =
    let url = Eliom_uri.make_string_uri ~absolute:true
                ~service:election_home (uuid, ()) |> rewrite_prefix
    in
    div [
        txt "The link to the election will be:";
        ul [li [txt url]];
      ]
  in
  let form_textarea =
    post_form ~a:[a_id "submit_form"; a_style "display:none;"]
      ~service:election_draft_credentials_post
      (fun name ->
       [div
          [div [txt "Public credentials:"];
           div [textarea ~a:[a_id "pks"; a_rows 5; a_cols 40] ~name ()];
           div [
               txt "Fingerprint of public credentials: ";
               span ~a:[a_id "public_creds_fp"] [];
             ];
           div [
               b [txt "Instructions:"];
               ol [
                   li [
                       txt "Download ";
                       a ~service:home ~a:[a_id "creds"] [txt "private credentials"] ();
                       txt " and save the file to a secure location.";
                       br ();
                       txt "You will use it to send credentials to voters.";
                     ];
                   li [
                       txt "Download ";
                       a ~service:home ~a:[a_id "voters_txt"] [txt "the list of voters"] ();
                       txt ".";
                       br ();
                       txt "This list must be the one approved by the election commission.";
                     ];
                   li [
                       txt "Save the two fingerprints above. ";
                       br ();
                       txt "Once the election is open, you must check that";
                       txt " they match with what is published by the server.";
                     ];
                   li [txt "Submit public credentials using the button below."];
                 ];
             ];
           div [input ~input_type:`Submit ~value:"Submit public credentials" string]]])
      (uuid, token)
  in
  let disclaimer =
    p
      [
        b [txt "Note:"];
        txt " submitting a large (> 200) number of credentials using the above form may fail; in this case, you have to use the command-line tool and the form below.";
      ]
  in
  let form_file =
    post_form
      ~service:election_draft_credentials_post_file
      (fun name ->
       [div
          [h2 [txt "Submit by file"];
           div [txt "Use this form to upload public credentials generated with the command-line tool."];
           div [file_input ~name ()];
           div [input ~input_type:`Submit ~value:"Submit" string]]])
      (uuid, token)
  in
  let group =
    div
      ~a:[a_style "display:none;"]
      [
        div [txt "UUID:"];
        div [unsafe_textarea "uuid" (raw_string_of_uuid uuid)];
        div [txt "Group parameters:"];
        div [unsafe_textarea "group" se.se_group];
      ]
  in
  let voters =
    let value = String.concat "\n" (List.map (fun x -> x.sv_id) se.se_voters) in
    let value = value ^ "\n" in
    let hash = Platform.sha256_b64 value in
    div [
      div [txt "List of voters:"];
      div [unsafe_textarea ~rows:5 ~cols:40 "voters" value];
      div [txt "Fingerprint of voters: "; txt hash];
    ]
  in
  let interactivity =
    div
      ~a:[a_id "interactivity"]
      [
        script ~a:[a_src (static "tool_js_credgen.js")] (txt "");
      ]
  in
  let div_textarea = div [group; voters; interactivity; form_textarea; disclaimer] in
  let content =
    if se.se_public_creds_received then (
      [
        div [txt "Credentials have already been generated!"];
      ]
    ) else (
      [
        div_link;
        div_textarea;
        form_file;
      ]
    ) in
  base ~title ~content ()

let election_draft_trustee token uuid se () =
  let title = "Trustee for election " ^ se.se_questions.t_name in
  let div_link =
    let url = Eliom_uri.make_string_uri ~absolute:true
                ~service:election_home (uuid, ()) |> rewrite_prefix
    in
    div [
        txt "The link to the election will be:";
        ul [li [txt url]];
      ]
  in
  let form =
    let trustee = List.find (fun x -> x.st_token = token) se.se_public_keys in
    let value = trustee.st_public_key in
    let service = Eliom_service.preapply ~service:election_draft_trustee_post (uuid, token) in
    post_form
      ~service
      (fun name ->
       [
         div ~a:[a_id "submit_form"; a_style "display:none;"] [
           div [txt "Public key:"];
           div [textarea ~a:[a_rows 5; a_cols 40; a_id "pk"] ~name ~value ()];
           div [
               txt "Fingerprint of the verification key: ";
               span ~a:[a_id "public_key_fp"] [];
             ];
           div [
               b [txt "Instructions:"];
               ol [
                   li [
                       txt "Download your ";
                       a ~service:home ~a:[a_id "private_key"] [txt "private key"] ();
                       txt " and save it to a secure location.";
                       br ();
                       txt "You will use it to decrypt the final result.";
                     ];
                   li [
                       txt "Save the fingerprint above.";
                       br ();
                       txt "Once the election is open, you must check that";
                       txt " it is present in the set of public keys";
                       txt " published by the server.";
                     ];
                   li [txt "Submit your public key using the button below."];
                 ];
             ];
           div [input ~input_type:`Submit ~value:"Submit public key" string];
         ]
       ]
      ) ()
  in
  let group =
    div
      ~a:[a_style "display:none;"]
      [
        div [txt "Group parameters:"];
        div [unsafe_textarea "group" se.se_group];
      ]
  in
  let interactivity =
    div
      ~a:[a_id "interactivity"]
      [
        script ~a:[a_src (static "tool_js_tkeygen.js")] (txt "");
      ]
  in
  let content = [
    div_link;
    group;
    interactivity;
    form;
  ] in
  base ~title ~content ()

let election_draft_threshold_trustee token uuid se () =
  let title = "Trustee for election " ^ se.se_questions.t_name in
  let header =
    div ~a:[a_style "text-align:center;"] [
        h2 [txt "Collaborative key generation"];
        div ~a:[a_id "current_step"] [
            txt "Step 0/3"
          ];
      ]
  in
  let div_link =
    let url = Eliom_uri.make_string_uri ~absolute:true
                ~service:election_home (uuid, ()) |> rewrite_prefix
    in
    div [
        txt "The link to the election will be:";
        ul [li [txt url]];
      ]
  in
  let%lwt trustee =
    match se.se_threshold_trustees with
    | None -> fail_http 404
    | Some ts ->
       match List.find_opt (fun x -> x.stt_token = token) ts with
       | Some x -> return x
       | None -> fail_http 404
  in
  let%lwt certs =
    match se.se_threshold_trustees with
    | None -> fail_http 404
    | Some ts ->
       let certs = List.fold_left (fun accu x ->
           match x.stt_cert with
           | None -> accu
           | Some c -> c :: accu
         ) [] ts |> List.rev |> Array.of_list
       in return {certs}
  in
  let threshold =
    match se.se_threshold with
    | None -> 0
    | Some t -> t
  in
  let inputs =
    div ~a:[a_style "display:none;"] [
        div [
            txt "Step: ";
            unsafe_textarea "step" (match trustee.stt_step with None -> "0" | Some x -> string_of_int x);
          ];
        div [
            txt "Group parameters: ";
            unsafe_textarea "group" se.se_group;
          ];
        div [
            txt "Certificates: ";
            unsafe_textarea "certs" (string_of_certs certs);
          ];
        div [
            txt "Threshold: ";
            unsafe_textarea "threshold" (string_of_int threshold);
          ];
        div [
            txt "Vinput: ";
            unsafe_textarea "vinput" (match trustee.stt_vinput with None -> "" | Some x -> string_of_vinput x);
          ];
        div [
            txt "Voutput: ";
            unsafe_textarea "voutput" (match trustee.stt_voutput with None -> "" | Some x -> x);
          ];
      ]
  in
  let form =
    post_form
      ~service:election_draft_threshold_trustee_post
      ~a:[a_id "data_form"]
      (fun data ->
        [
          div ~a:[a_id "key_helper"; a_style "display:none;"] [
              b [txt "Instructions:"];
              ol [
                  li [
                      txt "Download your ";
                      a ~service:home ~a:[a_id "private_key"] [txt "private key"] ();
                      txt " and save it to a secure location.";
                      br ();
                      txt "You will use it in the next steps and to decrypt the final result.";
                    ];
                  li [
                      txt "The fingerprint of your public key is ";
                      span ~a:[a_id "pki_fp"] [];
                      txt ". Save it so that you can check later that it appears on the election home.";
                    ];
                  li [
                      txt "Submit data using the following button: ";
                      input ~input_type:`Submit ~value:"Submit" string;
                      txt ".";
                      div [
                          txt "Data: ";
                          textarea ~a:[a_id "data"; a_rows 5; a_cols 40] ~name:data ();
                        ];
                    ];
                ];
            ];
        ]
      ) (uuid, token)
  in
  let form_compute =
    div ~a:[a_id "compute_form"; a_style "display: none;"] [
        b [txt "Instructions:"];
        ol [
            li [
                txt "Enter your private key: ";
                input ~input_type:`Text ~a:[a_id "compute_private_key"] string;
                txt " ";
                button_no_value ~a:[a_id "compute_button"] ~button_type:`Button [
                    txt "Proceed";
                  ];
              ];
            li [
                txt "Submit data using the following button:";
                post_form
                  ~service:election_draft_threshold_trustee_post
                  (fun data ->
                    [
                      input ~input_type:`Submit ~value:"Submit" string;
                      div [
                          txt "Data: ";
                          textarea ~a:[a_id "compute_data"; a_rows 5; a_cols 40] ~name:data ();
                        ];
                    ]
                  ) (uuid, token);
              ];
          ];
      ]
  in
  let interactivity =
    div
      ~a:[a_id "interactivity"]
      [
        script ~a:[a_src (static "tool_js_ttkeygen.js")] (txt "");
      ]
  in
  let div_instructions =
    div ~a:[a_id "div_instructions"; a_style "display: none;"]
      [
        b [txt "Instructions"];
        ol [
            li [txt "Save the fingerprint above."];
            li [txt "Once the election is open, you must check that it is present in the set of verification keys published by the server."];
            li [txt "Remember that you must also check the presence of your public key."];
            li [txt "Remember to store securely you private key."];
          ];
      ]
  in
  let content = [
      header;
      div_link;
      br ();
      div ~a:[a_id "explain"] [];
      inputs;
      interactivity;
      form;
      form_compute;
      div_instructions;
    ]
  in
  base ~title ~content ()

let election_draft_importer ~service ~title uuid (elections, tallied, archived) () =
  let format_election (from_uuid, name) =
    let from_uuid = raw_string_of_uuid from_uuid in
    let form = post_form ~service
      (fun from ->
        [
          div [
              txt name;
              txt " (";
              txt from_uuid;
              txt ")"
            ];
          div [
            input
              ~input_type:`Hidden
              ~name:from
              ~value:from_uuid string;
            input ~input_type:`Submit ~value:"Import from this election" string;
          ]
        ]
      ) uuid
    in
    li [form]
  in
  let itemize xs = match xs with
    | [] -> p [txt "You own no such elections!"]
    | _ -> ul @@ List.map format_election xs
  in
  let content = [
    h2 [txt "Elections you can administer"];
    itemize elections;
    h2 [txt "Tallied elections"];
    itemize tallied;
    h2 [txt "Archived elections"];
    itemize archived;
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let election_draft_import uuid se elections =
  let title = "Election " ^ se.se_questions.t_name ^ " — Import voters from another election" in
  let service = election_draft_import_post in
  election_draft_importer ~service ~title uuid elections

let election_draft_import_trustees uuid se elections =
  let title = "Election " ^ se.se_questions.t_name ^ " — Import trustees from another election" in
  let service = election_draft_import_trustees_post in
  election_draft_importer ~service ~title uuid elections

let election_draft_confirm uuid se () =
  let notok x = span ~a:[a_style "color: red;"] [txt x] in
  let ok x = txt x in
  let title = "Election " ^ se.se_questions.t_name ^ " — Validate creation" in
  let ready = true in
  let ready, name =
    if se.se_questions.t_name = default_name then
      false, notok "Not edited"
    else
      ready, ok "OK"
  in
  let ready, description =
    if se.se_questions.t_description = default_description then
      false, notok "Not edited"
    else
      ready, ok "OK"
  in
  let ready, admin_name =
    if se.se_administrator = None then
      false, notok "Missing"
    else
      ready, ok "OK"
  in
  let ready, questions =
    if se.se_questions.t_questions = default_questions then
      false, notok "Not edited"
    else
      ready, ok "OK"
  in
  let ready, voters =
    let b = not (se.se_voters = []) in
    ready && b,
    (if b then ok else notok) (Printf.sprintf "%d voter(s)" (List.length se.se_voters))
  in
  let ready, passwords =
    match se.se_metadata.e_auth_config with
    | Some [{auth_system = "password"; _}] ->
       if List.for_all (fun v -> v.sv_password <> None) se.se_voters then ready, ok "OK"
       else false, notok "Missing"
    | _ -> ready, ok "Not applicable"
  in
  let ready, credential_authority =
    match se.se_metadata.e_cred_authority with
    | None -> false, notok "Missing"
    | Some _ -> ready, ok "OK"
  in
  let cred_auth_is_server = se.se_metadata.e_cred_authority = Some "server" in
  let ready, credentials =
    if se.se_public_creds_received then
      ready, ok (if cred_auth_is_server then "Sent" else "Received")
    else false, notok "Missing"
  in
  let%lwt private_creds_downloaded =
    file_exists (!Web_config.spool_dir / raw_string_of_uuid uuid / "private_creds.downloaded")
  in
  let private_creds =
    if cred_auth_is_server && not private_creds_downloaded then
      span
        [
          notok "Not downloaded.";
          txt " Please ";
          a ~service:election_draft_credentials_get [txt "download"] uuid;
          txt " and save them securely.";
        ]
    else
      ok "OK"
  in
  let ready, trustees =
    match se.se_public_keys with
    | [] -> ready, ok "OK"
    | _ :: _ ->
       match se.se_threshold_trustees with
       | None -> if List.for_all (fun {st_public_key; _} ->
                        st_public_key <> ""
                      ) se.se_public_keys then ready, ok "OK" else false, notok "Missing"
       | Some _ ->
          if se.se_threshold_parameters <> None &&
               match se.se_threshold_trustees with
               | None -> false
               | Some ts ->
                  List.for_all (fun {stt_step; _} -> stt_step = Some 7) ts
          then ready, ok "OK"
          else false, notok "Missing"
  in
  let div_trustee_warning =
    match se.se_threshold_trustees, se.se_public_keys with
    | None, [] ->
       div [
           b [txt "Warning:"];
           txt " No trustees were set. This means that the server will manage the election key by itself.";
         ]
    | _, _ -> txt ""
  in
  let contact, div_contact_warning =
    match se.se_metadata.e_contact with
    | None ->
       "No",
       div [
           b [txt "Warning:"];
           txt " No contact was set!";
         ]
    | Some _ -> "Yes", txt ""
  in
  let table_checklist = table [
    tr [
      td [txt "Name?"];
      td [name];
    ];
    tr [
      td [txt "Description?"];
      td [description];
    ];
    tr [
        td [txt "Public name of the administrator?"];
        td [admin_name];
      ];
    tr [
      td [txt "Questions?"];
      td [questions; txt " "; preview_booth uuid];
    ];
    tr [
      td [txt "Voters?"];
      td [voters];
    ];
    tr [
      td [txt "Passwords?"];
      td [passwords];
    ];
    tr [
      td [txt "Credential authority?"];
      td [credential_authority];
    ];
    tr [
      td [txt "Credentials?"];
      td [credentials];
    ];
    tr [
      td [txt "Private credentials?"];
      td [private_creds];
    ];
    tr [
      td [txt "Trustees?"];
      td [trustees];
    ];
    tr [
      td [txt "Contact?"];
      td [txt contact];
    ];
  ] in
  let status =
    if ready then
      span ~a:[a_style "color: green;"] [txt "election ready"]
    else
      span ~a:[a_style "color: red;"] [txt "election not ready"]
  in
  let checklist = div [
    h2 [txt "Checklist: "; status];
    table_checklist;
    div_trustee_warning;
    div_contact_warning;
  ] in
  let form_create =
    if ready then
      post_form
        ~service:election_draft_create
        (fun () ->
          [div
              [h2 [txt "Validate creation"];
               input ~input_type:`Submit ~value:"Create election" string;
               txt " (Warning: this action is irreversible.)";
              ]]
        ) uuid
    else div []
  in
  let back = div [
    a ~service:Web_services.election_draft [txt "Return to draft page"] uuid;
  ] in
  let content = [
    back;
    checklist;
    form_create;
  ] in
  let%lwt login_box = login_box () in
  base ~title ~login_box ~content ()

let file uuid x = Eliom_service.preapply ~service:election_dir (uuid, x)

let audit_footer election =
  let uuid = election.e_params.e_uuid in
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  return @@ div ~a:[a_style "line-height:1.5em;"] [
    div [
      div [
        txt (s_ "Election fingerprint: ");
        code [ txt election.e_fingerprint ];
      ];
      div [
        txt (s_ "Audit data: ");
        a ~service:(file uuid ESRaw) [
          txt (s_ "parameters")
        ] ();
        txt ", ";
        a ~service:(file uuid ESTrustees) [txt "trustees"] ();
        txt ", ";
        a ~service:(file uuid ESCreds) [
          txt (s_ "public credentials")
        ] ();
        txt ", ";
        a ~service:(file uuid ESBallots) [
          txt (s_ "ballots")
        ] ();
        txt ".";
      ];
    ]
  ]

let rec list_concat elt = function
  | x :: ((_ :: _) as xs) -> x :: elt :: (list_concat elt xs)
  | ([_] | []) as xs -> xs

let format_question_result uuid l (i, q) r =
  let open (val l : Web_i18n_sig.GETTEXT) in
  match q with
  | Question.Homomorphic x ->
     let r = Shape.to_array r in
     let open Question_h_t in
     let answers = Array.to_list x.q_answers in
     let answers = match x.q_blank with
       | Some true -> s_ "Blank vote" :: answers
       | _ -> answers
     in
     let answers =
       List.mapi (fun j x ->
           tr [td [txt x]; td [txt @@ string_of_int r.(j)]]
         ) answers
     in
     let answers =
       match answers with
       | [] -> txt ""
       | y :: ys ->
          match x.q_blank with
          | Some true -> table (ys @ [y])
          | _ -> table (y :: ys)
     in
     li [
         div ~a:[a_class ["result_question"]] [txt x.q_question];
         answers;
       ]
  | Question.NonHomomorphic x ->
     let open Question_nh_t in
     li [
         div ~a:[a_class ["result_question"]] [txt x.q_question];
         div [
             txt (s_ "The raw results can be viewed in the ");
             a ~service:election_project_result [txt (s_ "JSON result")] ((uuid, ()), i);
             txt (s_ ". It contains all submitted ballots in clear, in random order. It is up to you to apply your favorite counting method (e.g. Condorcet, STV, majority judgement).");
             txt " ";
             txt (s_ "Available methods on this server:");
             txt " ";
             a ~service:method_schulze [txt "Schulze"] (uuid, i);
             txt ".";
           ];
       ]

let election_home election state () =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let params = election.e_params in
  let uuid = params.e_uuid in
  let%lwt dates = Web_persist.get_election_dates uuid in
  let now = now () in
  let state_ =
    match state with
    | `Closed ->
       let it_will_open =
         match dates.e_auto_open with
         | Some t when datetime_compare now t < 0 ->
            span [
                txt " ";
                txt (s_ "It will open in ");
                txt (format_period l (datetime_sub t now));
                txt ".";
              ]
         | _ -> txt ""
       in
      [
        txt " ";
        b [txt (s_ "This election is currently closed.")];
        it_will_open;
      ]
    | `Open ->
       let it_will_close =
         match dates.e_auto_close with
         | Some t when datetime_compare now t < 0 ->
            span [
                txt (s_ "The election will close in ");
                txt (format_period l (datetime_sub t now));
                txt ".";
              ]
         | _ -> txt ""
       in
       [it_will_close]
    | `Shuffling ->
       [
         txt " ";
         b [txt (s_ "The election is closed and being tallied.")];
       ]
    | `EncryptedTally _ ->
       [
         txt " ";
         b [txt (s_ "The election is closed and being tallied.")];
       ]
    | `Tallied ->
       [
         txt " ";
         b [txt (s_ "This election has been tallied.")];
       ]
    | `Archived ->
       [
         txt " ";
         b [txt (s_ "This election is archived.")];
       ]
  in
  let ballots_link =
    p ~a:[a_style "text-align:center;"] [
        a
          ~a:[a_style "font-size:25px;"]
          ~service:election_pretty_ballots [
            txt (s_ "See accepted ballots")
          ] (uuid, ())
      ]
  in
  let%lwt footer = audit_footer election in
  let go_to_the_booth =
    let disabled = match state with
      | `Open -> false
      | _ -> true
    in
    div ~a:[a_style "text-align:center;"] [
      div [
          let hash = Netencoding.Url.mk_url_encoded_parameters ["uuid", raw_string_of_uuid uuid; "lang", lang] in
          make_button ~service:election_vote ~hash ~style:"font-size:35px;" ~disabled (s_ "Start");
        ];
      div [
        a
          ~service:(Eliom_service.preapply ~service:election_cast uuid)
          [txt (s_ "Advanced mode")] ();
      ];
    ]
  in
  let%lwt middle =
    let%lwt result = Web_persist.get_election_result uuid in
    let%lwt hidden = Web_persist.get_election_result_hidden uuid in
    let%lwt is_admin =
      let%lwt metadata = Web_persist.get_election_metadata uuid in
      let%lwt site_user = Eliom_reference.get Web_state.site_user in
      return (metadata.e_owner = site_user)
    in
    match result with
    | Some r when hidden = None || is_admin ->
       let result = Shape.to_shape_array r.result in
       return @@ div [
         ul (
             Array.map2 (format_question_result uuid l) (Array.mapi (fun i q -> i, q) election.e_params.e_questions) result
             |> Array.to_list
           );
         div [
           txt (s_ "Number of accepted ballots: ");
           txt (string_of_int r.num_tallied);
         ];
         div [
           txt (s_ "You can also download the ");
           a ~service:election_dir
             [txt (s_ "result with cryptographic proofs")]
             (uuid, ESResult);
           txt ".";
         ];
       ]
    | Some _ ->
       let t =
         match hidden with
         | Some t -> t
         | None -> failwith "Impossible case in election_admin"
       in
       return @@
         div [
             Printf.ksprintf txt
               (f_ "The result of this election is currently not publicly available. It will be in %s.")
               (format_period l (datetime_sub t now));
           ]
    | None -> return go_to_the_booth
  in
  let languages =
    div ~a:[a_class ["languages"]]
      (list_concat (txt " ") @@ List.map (fun lang ->
        a ~service:set_language [txt lang] (lang, ContSiteElection uuid)
       ) available_languages)
  in
  let%lwt scd = Eliom_reference.get Web_state.show_cookie_disclaimer in
  let cookie_disclaimer =
    if scd then
      div
        ~a:[a_style "border-style: solid; border-width: 1px;"]
        [
          txt (s_ "By using this site, you accept our ");
          unsafe_a !Web_config.gdpr_uri (s_ "personal data policy");
          txt ". ";
          a ~service:set_cookie_disclaimer [txt (s_ "Accept")] (ContSiteElection uuid);
        ]
    else txt ""
  in
  let%lwt cache = Web_persist.get_audit_cache uuid in
  let checksums = cache.cache_checksums in
  let div_admin =
    div [
        Printf.ksprintf txt
          "This election is administered by %s."
          (Option.get params.e_administrator "N/A");
      ]
  in
  let div_voters =
    div [
        txt "The ";
        b [txt "voter list"];
        txt " has ";
        txt (string_of_int cache.cache_num_voters);
        txt " voter(s) and ";
        b [txt "fingerprint"];
        txt " ";
        txt cache.cache_voters_hash;
        txt ".";
      ]
  in
  let format_tc id xs =
    ul ~a:[a_id id] (
        List.map
          (fun x ->
            let name = Option.get x.tc_name "N/A" in
            li [Printf.ksprintf txt "%s (%s)" name x.tc_checksum]
          ) xs
      )
  in
  let div_trustees_mandatory =
    match checksums.ec_trustees with
    | [] -> txt ""
    | l ->
       div [
           txt "All of the following trustees (";
           b [txt "verification keys"];
           txt ") are needed to decrypt the result:";
           format_tc "trustees" l;
         ]
  in
  let format_ttc className xs =
    ul ~a:[a_class [className]] (
        List.map
          (fun x ->
            let name = Option.get x.ttc_name "N/A" in
            li [
                Printf.ksprintf txt "%s (%s) [%s]"
                  name x.ttc_verification_key x.ttc_pki_key
              ]
          ) xs
      )
  in
  let divs_trustees_threshold =
    match checksums.ec_trustees_threshold with
    | None -> []
    | Some l ->
       List.map
         (fun x ->
           div [
               Printf.ksprintf txt "%d of the following %d trustees ("
                 x.ts_threshold (List.length x.ts_trustees);
               b [txt "verification keys"];
               txt ") [";
               b [txt "public keys"];
               txt "] are needed to decrypt the election result:";
               format_ttc "trustees_threshold" x.ts_trustees;
             ]
         ) l
  in
  let div_trustees = div (div_trustees_mandatory :: divs_trustees_threshold) in
  let div_credentials =
    div [
        Printf.ksprintf txt
          "Credentials were generated and sent by %s and have fingerprint %s."
          (Option.get params.e_credential_authority "N/A")
          checksums.ec_public_credentials;
      ]
  in
  let div_shuffles =
    match checksums.ec_shuffles with
    | None -> txt ""
    | Some xs ->
       div [
           txt "Trustees shuffled the ballots in the following order:";
           format_tc "shuffles" xs;
         ]
  in
  let div_tally =
    match checksums.ec_encrypted_tally with
    | None -> txt ""
    | Some x ->
       div [
           Printf.ksprintf txt
             "The fingerprint of the encrypted tally is %s."
             x
         ]
  in
  let div_audit =
    div ~a:[a_class ["hybrid_box"]] [
      div_admin;
      div_voters;
      div_trustees;
      div_credentials;
      div_shuffles;
      div_tally;
    ]
  in
  let content = [
    cookie_disclaimer;
    languages;
    p state_;
    br ();
    middle;
    br ();
    ballots_link;
    br ();
    div_audit;
  ] in
  base ~title:params.e_name ~content ~footer ~uuid ()

let mail_trustee_tally : ('a, 'b, 'c, 'd, 'e, 'f) format6 =
  "Dear trustee,

The election is now closed. Here's the link to proceed to tally:

  %s

Here's the instructions:
1. Follow the link.
2. Enter your private decryption key in the first box and click on
   \"generate decryption factors\"
3. The second box is now filled with crypto material. Please press the
   button \"submit\".

Thank you again for your help,

-- \nThe election administrator."

let mail_shuffle : ('a, 'b, 'c, 'd, 'e, 'f) format6 =
  "Dear trustee,

You will find below the link to shuffle encrypted ballots.

  %s

Here's the instructions:
1. click on the link
2. click on \"Compute shuffle\"
3. the fingerprint of your shuffle will appear. Save it.
4. when the election result is published, make sure that the fingerprint of
   your shuffle appears in the result.

Thank you for your help,

-- \nThe election administrator."

type web_shuffler = {
    ws_trustee : string;
    mutable ws_select : string option;
    mutable ws_hash : string option;
}

let election_admin ?shuffle_token ?tally_token election metadata state get_tokens_decrypt () =
  let uuid = election.e_params.e_uuid in
  let title = election.e_params.e_name ^ " — Administration" in
  let auto_form () =
    let open Web_persist in
    let%lwt dates = get_election_dates uuid in
    let format = function
      | None -> ""
      | Some x -> String.sub (string_of_datetime x) 1 19
    in
    return @@ post_form ~service:election_auto_post
      (fun (lopen, lclose) ->
        [
          div [txt "Alternatively, you may setup automatic dates."];
          div [
              b [txt "Note:"];
              txt " times are in UTC. Now is ";
              txt (format (Some (now ())));
              txt ".";
            ];
          div ~a:[a_style "margin-left: 3em;"] [
              div [
                  txt "Automatically open the election at: ";
                  input ~name:lopen ~input_type:`Text ~value:(format dates.e_auto_open) string;
                ];
              div [
                  txt "Automatically close the election at: ";
                  input ~name:lclose ~input_type:`Text ~value:(format dates.e_auto_close) string;
                ];
              div [
                  txt "Enter dates in UTC, in format YYYY-MM-DD HH:MM:SS, leave empty for no date.";
                ];
            ];
          div [
              input ~input_type:`Submit ~value:"Change automatic dates" string;
            ];
        ]
      ) uuid
  in
  let state_form checked =
    let service, value, msg, msg2 =
      if checked then
        election_close, "Close election",
        "The election is open. Voters can vote. ",
        " You may re-open the election when it is closed."
      else
        election_open, "Open election",
        "The election is closed. No one can vote. ",
        ""
    in
    post_form
      ~service
      (fun () ->
       [
         div ~a:[a_style "text-align: center;"] [
             txt msg;
           ];
         br ();
         input ~input_type:`Submit ~value string;
         txt msg2;
       ]) uuid
  in
  let%lwt state_div =
    match state with
    | `Open ->
       let%lwt auto_form = auto_form () in
       return @@ div [
         state_form true;
         br ();
         auto_form;
       ]
    | `Closed ->
       let%lwt auto_form = auto_form () in
       return @@ div [
         state_form false;
         br ();
         auto_form;
         br ();
         hr ();
         post_form
           ~service:election_compute_encrypted_tally
           (fun () ->
             [input
                 ~input_type:`Submit
                 ~value:"Proceed to vote counting"
                 string;
              txt " Warning: this action is irreversible; the election will be definitively closed.";
             ]) uuid;
       ]
    | `Shuffling ->
       let shufflers =
         match metadata.e_trustees with
         | None -> [{ws_trustee = "server"; ws_select = None; ws_hash = None}]
         | Some ts ->
            List.map
              (fun ws_trustee ->
                {ws_trustee; ws_select = None; ws_hash = None}
              ) ts
       in
       let%lwt () =
         match%lwt Web_persist.get_shuffle_hashes uuid with
         | None -> failwith "shuffle fingerprints are missing"
         | Some hashes ->
            List.iter
              (fun x ->
                match List.find_opt (fun y -> y.ws_trustee = x.sh_trustee) shufflers with
                | Some y -> y.ws_hash <- Some x.sh_hash
                | None -> ()
              ) hashes;
            return_unit
       in
       let%lwt select_disabled =
         match%lwt Web_persist.get_shuffle_token uuid with
         | None -> return_false
         | Some t ->
            match List.find_opt (fun x -> x.ws_trustee = t.tk_trustee) shufflers with
            | Some y -> y.ws_select <- Some t.tk_token; return_true
            | None -> return_false
       in
       let table_contents =
         List.map
           (fun x ->
             let skip, hash, done_ =
               let mk_skip disabled =
                 post_form ~service:election_shuffler_skip_confirm
                   (fun (nuuid, ntrustee) ->
                     let a = if disabled then [a_disabled ()] else [] in
                     [
                       input ~input_type:`Hidden ~name:nuuid ~value:(raw_string_of_uuid uuid) string;
                       input ~input_type:`Hidden ~name:ntrustee ~value:x.ws_trustee string;
                       input ~a ~input_type:`Submit ~value:"Skip" string;
                     ]
                   ) ()
               in
               match x.ws_hash with
               | None -> mk_skip false, txt "", false
               | Some h -> mk_skip true, txt (if h = "" then "(skipped)" else h), true
             in
             let this_line =
               match shuffle_token with
                 | Some y when x.ws_select = Some y -> true
                 | _ -> false
             in
             let first_line =
               tr
                 [
                   td [txt x.ws_trustee];
                   td
                     [
                       match x.ws_select with
                       | Some token ->
                          let uri =
                            rewrite_prefix @@
                              Eliom_uri.make_string_uri
                                ~absolute:true ~service:election_shuffle_link (uuid, token)
                          in
                          let body = Printf.sprintf mail_shuffle uri in
                          let subject = "Link to shuffle encrypted ballots" in
                          div
                            [
                              a_mailto ~dest:x.ws_trustee ~subject ~body "Mail";
                              txt " | ";
                              if this_line then
                                a ~service:election_admin [txt "Hide link"] uuid
                              else
                                a ~service:election_shuffle_link ~a:[a_id "shuffle-link"] [txt "Link"] (uuid, token)
                            ]
                       | None ->
                          post_form ~service:election_shuffler_select
                            (fun (nuuid, ntrustee) ->
                              let a = if select_disabled || done_ then [a_disabled ()] else [] in
                              [
                                input ~input_type:`Hidden ~name:nuuid ~value:(raw_string_of_uuid uuid) string;
                                input ~input_type:`Hidden ~name:ntrustee ~value:x.ws_trustee string;
                                input ~a ~input_type:`Submit ~value:"Select this trustee" string;
                              ]
                            ) ()
                     ];
                   td [if done_ then txt "Yes" else txt "No"];
                   td [skip];
                   td [hash];
                 ]
             in
             let second_line =
               match this_line, x.ws_select with
               | true, Some token ->
                  [
                    tr
                      [
                        td ~a:[a_colspan 5]
                          [
                            txt "The link that must be sent to trustee ";
                            txt x.ws_trustee;
                            txt " is:";
                            br ();
                            Eliom_uri.make_string_uri ~absolute:true
                              ~service:election_shuffle_link (uuid, token)
                            |> rewrite_prefix |> txt
                          ]
                      ]
                  ]
               | _, _ -> []
             in
             first_line :: second_line
           ) shufflers
       in
       let proceed =
         if List.for_all (fun x -> x.ws_hash <> None) shufflers then
           post_form ~service:election_decrypt
             (fun () ->
               [
                 input ~input_type:`Submit ~value:"Proceed to decryption" string;
               ]
             ) uuid
         else
           txt ""
       in
       return (
           div [
               div [
                   div ~a:[a_style "text-align: center;"]
                     [txt "Shuffling of ballots"];
                   table
                     (tr
                        [
                          th [txt "Trustee"];
                          th [];
                          th [txt "Done?"];
                          th [];
                          th [txt "Fingerprint"];
                        ] :: (List.flatten table_contents)
                     );
                 ];
               proceed;
             ]
         )
    | `EncryptedTally _ ->
       let%lwt pds = Web_persist.get_partial_decryptions uuid in
       let%lwt trustees = Web_persist.get_trustees uuid in
       let trustees = trustees_of_string Yojson.Safe.read_json trustees in
       let threshold, npks =
         let rec loop trustees threshold npks =
           match trustees with
           | [] -> threshold, npks
           | `Single _ :: ts -> loop ts threshold (npks + 1)
           | `Pedersen t :: ts ->
              match threshold with
              | Some _ -> failwith "Unsupported: two Pedersen"
              | None -> loop ts (Some t.t_threshold) (npks + Array.length t.t_verification_keys)
         in
         loop trustees None 0
       in
       let threshold_or_not =
         match threshold with
         | None -> txt ""
         | Some x -> txt (Printf.sprintf " At least %d trustee(s) must act." x)
       in
       let trustees =
         let rec loop i ts =
           if i <= npks then
             match ts with
             | t :: ts -> (Some t, i) :: (loop (i+1) ts)
             | [] -> (None, i) :: (loop (i+1) ts)
           else []
         in
         match metadata.e_trustees with
         | None -> loop 1 []
         | Some ts -> loop 1 ts
       in
       let rec seq i j = if i >= j then [] else i :: (seq (i+1) j) in
       let%lwt trustee_tokens =
         match threshold with
         | None -> return (List.map string_of_int (seq 1 (npks+1)))
         | Some _ -> get_tokens_decrypt ()
       in
       let trustees = List.combine trustees trustee_tokens in
       let trustees =
         List.map
           (fun ((name, trustee_id), token) ->
             let this_line =
               match tally_token with
               | Some x when x = token -> true
               | _ -> false
             in
             let service = election_tally_trustees in
             let x = (uuid, token) in
             let uri = rewrite_prefix @@ Eliom_uri.make_string_uri
               ~absolute:true ~service x
             in
             let link_content, dest = match name with
               | None -> uri, !Web_config.server_mail
               | Some name -> name, name
             in
             let mail, link =
               if link_content = "server" then (
                 txt "(server)",
                 txt "(server)"
               ) else (
                 let body = Printf.sprintf mail_trustee_tally uri in
                 let subject = "Link to tally the election" in
                 a_mailto ~dest ~subject ~body "Mail",
                 if this_line then
                   a ~service:election_admin [txt "Hide link"] uuid
                 else
                   a ~service [txt "Link"] x
               )
             in
             let first_line =
               tr [
                   td [txt link_content];
                   td [mail];
                   td [link];
                   td [
                       txt (if List.mem_assoc trustee_id pds then "Yes" else "No")
                     ];
                 ]
             in
             let second_line =
               if this_line then
                 [
                   tr
                     [
                       td ~a:[a_colspan 4]
                         [
                           txt "The link that must be sent to trustee ";
                           txt link_content;
                           txt " is:";
                           br ();
                           txt uri;
                         ]
                     ]
                 ]
               else []
             in
             first_line :: second_line
           ) trustees
       in
       let release_form =
         post_form
           ~service:election_tally_release
           (fun () ->
             [input
                 ~input_type:`Submit
                 ~value:"Compute the result"
                 string
             ]) uuid
       in
       return @@ div [
         div [
           txt "The ";
           a
             ~service:election_dir
             [txt "encrypted tally"]
             (uuid, ESETally);
           txt " has been computed."
         ];
         div [
           div [txt "We are now waiting for trustees..."; threshold_or_not];
           table
             (tr [
               th [txt "Trustee"];
               th [txt "Mail"];
               th [txt "Link"];
               th [txt "Done?"];
             ] :: List.flatten trustees)
         ];
         release_form;
       ]
    | `Tallied ->
       let%lwt hidden = Web_persist.get_election_result_hidden uuid in
       let form_toggle =
         match hidden with
         | Some _ ->
            post_form ~service:election_show_result
              (fun () ->
                [input ~input_type:`Submit ~value:"Publish the result now" string]
              ) uuid
         | None ->
            post_form ~service:election_hide_result
              (fun date ->
                [
                  div [
                      Printf.ksprintf txt "You may postpone the publication of the election result up to %d days in the future." days_to_publish_result;
                    ];
                  div [
                      input ~input_type:`Submit ~value:"Postpone publication until" string;
                      txt " ";
                      input ~name:date ~input_type:`Text string;
                    ];
                  div [
                      txt "Enter the date in UTC, in format YYYY-MM-DD HH:MM:SS. For example, now is ";
                      txt (String.sub (string_of_datetime (now ())) 1 19);
                      txt ".";
                    ];
                ]
              ) uuid
       in
       return @@ div [
         div [txt "This election has been tallied."];
         br ();
         hr ();
         form_toggle;
       ]
    | `Archived ->
       return @@ div [
         txt "This election is archived. ";
         a ~service:election_download_archive [
             txt "Download archive.";
           ] (uuid, ());
       ]
  in
  let%lwt dates = Web_persist.get_election_dates uuid in
  let%lwt archive_date = match state with
    | `Tallied ->
       let t = Option.get dates.e_tally default_tally_date in
       let t = datetime_add t (day days_to_archive) in
       return @@
         div [
             txt "This election will be automatically archived after ";
             txt (format_datetime t);
             txt ".";
           ]
    | _ -> return @@ txt ""
  in
  let div_archive = match state with
    | `Archived -> txt ""
    | _ -> div [
      br ();
      hr ();
      archive_date;
      post_form ~service:election_archive (fun () ->
        [
          input ~input_type:`Submit ~value:"Archive election" string;
          txt " Warning: this action is irreversible. Archiving an election makes it read-only; in particular, the election will be definitively closed (no vote submission, no vote counting).";
        ]
      ) uuid;
    ]
  in
  let%lwt deletion_date = match state with
    | `Open | `Closed | `Shuffling | `EncryptedTally _ ->
       let t = Option.get dates.e_finalization default_validation_date in
       return @@ datetime_add t (day days_to_delete)
    | `Tallied ->
       let t = Option.get dates.e_tally default_tally_date in
       return @@ datetime_add t (day (days_to_archive + days_to_delete))
    | `Archived ->
       let t = Option.get dates.e_archive default_archive_date in
       return @@ datetime_add t (day days_to_delete)
  in
  let div_delete =
    div [
        br ();
        hr ();
        div [
            txt "This election will be automatically deleted after ";
            txt (format_datetime deletion_date);
            txt ".";
          ];
        post_form ~service:election_delete (fun () ->
            [
              input ~input_type:`Submit ~value:"Delete election" string;
              txt " Warning: this action is irreversible.";
            ]
          ) uuid;
      ]
  in
  let cas = match metadata.e_auth_config with
    | Some [{auth_system = "cas"; _}] -> true
    | _ -> false
  in
  let div_regenpwd =
    if cas then
      txt ""
    else
      div [
          a ~a:[a_id "election_regenpwd"] ~service:election_regenpwd [txt "Regenerate and mail a password"] uuid;
        ]
  in
  let content = [
    div [
      a ~service:Web_services.election_home [txt "Election home"] (uuid, ());
    ];
    div [
      a ~service:election_dir [txt "Voter list"] (uuid, ESVoters);
    ];
    div [
      a ~service:election_pretty_records [txt "Voting records"] (uuid, ());
    ];
    div [
      a ~service:election_missing_voters [txt "Missing voters"] (uuid, ());
    ];
    div_regenpwd;
    hr ();
    div [state_div];
    div_archive;
    div_delete;
  ] in
  let%lwt login_box = login_box ~cont:(ContSiteElection uuid) () in
  base ~title ~login_box ~content ()

let regenpwd uuid () =
  let form = post_form ~service:election_regenpwd_post
    (fun user ->
      [
        div [
          txt "Username: ";
          input ~name:user ~input_type:`Text string;
        ];
        div [input ~input_type:`Submit ~value:"Submit" string];
      ]
    ) uuid
  in
  let content = [ form ] in
  let title = "Regenerate and mail password" in
  let%lwt login_box = login_box ~cont:(ContSiteElection uuid) () in
  base ~title ~login_box ~content ~uuid ()

let cast_raw election () =
  let params = election.e_params in
  let uuid = params.e_uuid in
  let form_rawballot = post_form ~service:election_submit_ballot
    (fun name ->
      [
        div [txt "Please paste your encrypted ballot in JSON format in the following box:"];
        div [textarea ~a:[a_rows 10; a_cols 40] ~name ()];
        div [input ~input_type:`Submit ~value:"Submit" string];
      ]
    ) ()
  in
  let form_upload = post_form ~service:election_submit_ballot_file
    (fun name ->
      [
        div [txt "Alternatively, you can also upload a file containing your ballot:"];
        div [
          txt "File: ";
          file_input ~name ();
        ];
        div [input ~input_type:`Submit ~value:"Submit" string];
      ]
    ) ()
  in
  let intro = div [
    div [
      txt "You can create an encrypted ballot by using the command line tool ";
      txt "(available in the ";
      a ~service:source_code [txt "sources"] ();
      txt "), or any booth (you can use the ";
      a ~service:election_vote [txt "booth of this server"] ();
      txt " or any other booth of the same version). A specification of encrypted ballots is also available in the sources.";
    ];
    div [
      a ~service:Web_services.election_home
        [txt "Back to election home"] (uuid, ());
    ];
  ] in
  let content = [
    intro;
    h3 [ txt "Submit by copy/paste" ];
    form_rawballot;
    h3 [ txt "Submit by file" ];
    form_upload;
  ] in
  let%lwt footer = audit_footer election in
  base ~title:params.e_name ~content ~uuid ~footer ()

let cast_confirmation election hash () =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let params = election.e_params in
  let uuid = params.e_uuid in
  let%lwt user = Web_state.get_election_user uuid in
  let name = params.e_name in
  let user_div = match user with
    | Some u ->
      post_form ~service:election_cast_confirm (fun () -> [
        p ~a:[a_style "text-align: center; padding: 10px;"] [
          txt (s_ "I am ");
          format_user ~site:false u;
          txt (s_ " and ");
          input
            ~a:[a_style "font-size: 20px; cursor: pointer;"]
            ~input_type:`Submit ~value:(s_ "I cast my vote") string;
          txt ".";
        ]
      ]) uuid
    | None ->
      div [
        txt (s_ "Please log in to confirm your vote.");
      ]
  in
  let%lwt div_revote =
    match user with
    | None -> return @@ txt ""
    | Some u ->
       let%lwt revote = Web_persist.has_voted uuid u in
       if revote then
         return @@ p [b [txt (s_ "Note: you have already voted. Your vote will be replaced.")]]
       else
         return @@ txt ""
  in
  let progress = div ~a:[a_style "text-align:center;margin-bottom:20px;"] [
    txt (s_ "Input credential");
    txt " — ";
    txt (s_ "Answer to questions");
    txt " — ";
    txt (s_ "Review and encrypt");
    txt " — ";
    txt (s_ "Authenticate");
    txt " — ";
    b [txt (s_ "Confirm")];
    txt " — ";
    txt (s_ "Done");
    hr ();
  ] in
  let content = [
    progress;
    div ~a:[a_class ["current_step"]] [
        txt (s_ "Step 5/6: Confirm");
    ];
    p [
      txt (s_ "Your ballot for ");
      em [txt name];
      txt (s_ " has been received, but not recorded yet. ");
      txt (s_ "Your smart ballot tracker is ");
      b ~a:[a_id "ballot_tracker"] [
        txt hash
      ];
      txt ".";
      br ();
    ];
    br ();
    p [txt (s_ "Note: your ballot is encrypted and nobody can see its contents.")];
    div_revote;
    user_div;
    p [
      (let service =
        Eliom_service.preapply
          ~service:Web_services.election_home (uuid, ())
      in
      a ~service [
        txt (s_ "Go back to election")
      ] ());
      txt ".";
    ];
  ] in
  base ~title:name ~content ~uuid ()

let lost_ballot election () =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let title = election.e_params.e_name in
  let uuid = election.e_params.e_uuid in
  let service = Web_services.election_vote in
  let hash = Netencoding.Url.mk_url_encoded_parameters ["uuid", raw_string_of_uuid uuid] in
  let content =
    [
      div [
          b [txt "Warning:"];
          txt " Your vote was not recorded!";
        ];
      div [
          txt "If you want to vote, you must ";
          make_a_with_hash ~service ~hash "start from the beginning";
          txt ".";
        ];
      div [
          a ~service:Web_services.election_home [
              txt (s_ "Go back to election")
            ] (uuid, ());
        ];
    ]
  in
  base ~title ~content ~uuid ()

let cast_confirmed election ~result () =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let params = election.e_params in
  let uuid = params.e_uuid in
  let name = params.e_name in
  let progress = div ~a:[a_style "text-align:center;margin-bottom:20px;"] [
    txt (s_ "Input credential");
    txt " — ";
    txt (s_ "Answer to questions");
    txt " — ";
    txt (s_ "Review and encrypt");
    txt " — ";
    txt (s_ "Authenticate");
    txt " — ";
    txt (s_ "Confirm");
    txt " — ";
    b [txt (s_ "Done")];
    hr ();
  ] in
  let result, step_title =
    match result with
    | Ok hash ->
       [txt (s_ " has been accepted.");
        txt " ";
        txt (s_ "Your smart ballot tracker is ");
        b ~a:[a_id "ballot_tracker"] [
          txt hash
        ];
        txt ". ";
        txt (s_ "You can check its presence in the ");
        a ~service:election_pretty_ballots [txt (s_ "ballot box")] (uuid, ());
        txt (s_ " anytime during the election.");
        txt (s_ " A confirmation e-mail has been sent to you.");
       ], s_ "Thank you for voting!"
    | Error e ->
       [txt (s_ " is rejected, because ");
        txt (Web_common.explain_error l e);
        txt ".";
       ], s_ "FAIL!"
  in
  let content = [
    progress;
    div ~a:[a_class ["current_step"]] [
        txt (s_ "Step 6/6: ");
        txt step_title;
    ];
    p ([
      txt (s_ "Your ballot for ");
      em [txt name];
      ] @ result);
    p
      [a
         ~service:Web_services.election_home
         [txt (s_ "Go back to election")]
         (uuid, ())];
  ] in
  base ~title:name ~content ~uuid ()

let pretty_ballots election hashes result () =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let params = election.e_params in
  let uuid = params.e_uuid in
  let title = params.e_name ^ " — " ^ s_ "Accepted ballots" in
  let nballots = ref 0 in
  let hashes = List.sort compare_b64 hashes in
  let ballots =
    List.map
      (fun h ->
       incr nballots;
       li
         [a
            ~service:election_pretty_ballot
            [txt h]
            ((uuid, ()), h)]
      ) hashes
  in
  let links =
    p
      [a
         ~service:Web_services.election_home
         [txt (s_ "Go back to election")]
         (uuid, ())]
  in
  let number = match !nballots, result with
    | n, None ->
       div [
         txt (string_of_int n);
         txt (s_ " ballot(s) have been accepted so far.");
       ]
    | n, Some r when n = r.num_tallied ->
       div [
         txt (string_of_int n);
         txt (s_ " ballot(s) have been accepted.");
       ]
    | n, Some r -> (* should not happen *)
       div [
         txt (string_of_int n);
         txt (s_ " ballot(s) have been accepted, and ");
         txt (string_of_int r.num_tallied);
         txt (s_ " have been tallied.");
       ]
  in
  let content = [
    number;
    ul ballots;
    links;
  ] in
  base ~title ~content ~uuid ()

let pretty_records election records () =
  let uuid = election.e_params.e_uuid in
  let title = election.e_params.e_name ^ " — Records" in
  let records = List.map (fun (date, voter) ->
    tr [td [txt date]; td [txt voter]]
  ) records in
  let table = match records with
    | [] -> div [txt "Nobody voted!"]
    | _ ->
       div [
         table
           (tr [th [txt "Date/Time (UTC)"]; th [txt "Username"]]
            :: records);
       ]
  in
  let content = [
    div [
      txt "You can also access the ";
      a ~service:election_dir [txt "raw data"] (uuid, ESRecords);
      txt ".";
    ];
    table;
  ] in
  let%lwt login_box = login_box ~cont:(ContSiteElection uuid) () in
  base ~title ~login_box ~content ()

let election_shuffler_skip_confirm uuid trustee =
  let title = "Skipping trustee " ^ trustee in
  let content =
    [
      post_form ~service:election_shuffler_skip
        (fun (nuuid, ntrustee) ->
          [
            div [txt "You may skip a trustee if they do not answer. Be aware that this reduces the security."];
            div
              [
                input ~input_type:`Hidden ~name:nuuid ~value:(raw_string_of_uuid uuid) string;
                input ~input_type:`Hidden ~name:ntrustee ~value:trustee string;
                input ~input_type:`Submit ~value:"Confirm" string;
                txt " ";
                a ~service:Web_services.election_admin [txt "Cancel"] uuid;
              ]
          ]
        ) ()
    ]
  in
  base ~title ~content ()

let shuffle election token =
  let params = election.e_params in
  let uuid = params.e_uuid in
  let title = params.e_name ^ " — Shuffle" in
  let content = [
      div [txt "As a trustee, your first role is to shuffle the encrypted ballots."];
      div [
          txt "Current list of ballots: ";
          unsafe_textarea ~rows:5 ~cols:40 "current_ballots" "";
          txt " ";
          let service = Eliom_service.preapply ~service:election_nh_ciphertexts uuid in
          make_button ~service ~disabled:false "Download as a file";
        ];
      div ~a:[a_id "estimation"] [
          txt "Estimating computation time...";
        ];
      div ~a:[a_id "wait_div"] [
          txt "Please wait... ";
          img ~src:(static "encrypting.gif") ~alt:"Loading..." ();
        ];
      div ~a:[a_id "controls_div"; a_style "display: none;"] [
          button_no_value ~button_type:`Button ~a:[a_id "compute_shuffle"] [txt "Compute shuffle"];
        ];
      post_form ~service:election_shuffle_post
        ~a:[a_id "submit_form"]
        (fun nshuffle ->
          [
            div [
                txt "Shuffled list of ballots: ";
                textarea ~a:[a_rows 5; a_cols 40; a_id "shuffle"] ~name:nshuffle ();
              ];
            div ~a:[a_id "hash_div"; a_style "display:none;"] [
                div [
                    txt "The fingerprint of your shuffle is: ";
                    b ~a:[a_id "hash"] [];
                    txt ".";
                  ];
                div [txt "You must record this fingerprint and check that it appears on the result page of the election."];
              ];
            div [
                input ~input_type:`Submit ~value:"Submit" string;
              ];
          ]
        ) (uuid, token);
      div [
          script ~a:[a_src (static "tool_js_shuffle.js")] (txt "");
        ];
    ]
  in
  base ~title ~content ~uuid ()

let tally_trustees election trustee_id token () =
  let params = election.e_params in
  let uuid = params.e_uuid in
  let title =
    params.e_name ^ " — Partial decryption #" ^ string_of_int trustee_id
  in
  let%lwt encrypted_private_key =
    match%lwt Web_persist.get_private_keys uuid with
    | None -> return_none
    | Some keys ->
       (* there is one Pedersen trustee *)
       let%lwt trustees = Web_persist.get_trustees uuid in
       let trustees = trustees_of_string Yojson.Safe.read_json trustees in
       let rec loop i ts =
         match ts with
         | [] -> return_none (* an error, actually *)
         | `Single _ :: ts -> loop (i - 1) ts
         | `Pedersen _ :: _ -> return_some (List.nth keys i)
       in
       loop (trustee_id - 1) trustees
  in
  let content = [
    p [txt "It is now time to compute your partial decryption factors."];
    p [
      txt "The fingerprint of the encrypted tally is ";
      b [span ~a:[a_id "hash"] []];
      txt "."
    ];
    (
      match encrypted_private_key with
      | None -> txt ""
      | Some epk ->
         div ~a:[a_style "display:none;"] [
             unsafe_textarea "encrypted_private_key" epk
           ];
    );
    hr ();
    div [
        b [txt "Instructions:"];
        ol [
            li [
                div ~a:[a_id "input_private_key"] [
                    div [
                        p [txt "Please enter your private key:"];
                        input
                          ~a:[a_id "private_key"; a_size 80]
                          ~input_type:`Text
                          string;
                      ];
                    div [
                        p [txt "Or load it from a file:"];
                        input
                          ~a:[a_id "private_key_file"]
                          ~input_type:`File
                          string;
                      ];
                  ];
                br ();
              ];
            li [
                div [
                    button_no_value
                      ~a:[a_id "compute"]
                      ~button_type:`Button
                      [txt "Compute decryption factors"];
                  ];
                br ();
              ];
            li [
                div ~a:[a_id "pd_done"] [
                    post_form
                      ~service:election_tally_trustees_post
                      (fun pd ->
                        [
                          div [
                              input ~input_type:`Submit ~value:"Submit" string;
                              txt " your contribution to decryption.";
                            ];
                          div [
                              txt "Data: ";
                              textarea
                                ~a:[a_rows 5; a_cols 40; a_id "pd"]
                                ~name:pd
                                ();
                            ];
                        ]
                      ) (uuid,  token);
                  ];
              ];
          ];
      ];
    div [
      script ~a:[a_src (static "tool_js_pd.js")] (txt "");
    ]
  ] in
  base ~title ~content ~uuid ()

let login_choose auth_systems service () =
  let auth_systems =
    auth_systems |>
    List.map (fun name ->
      a ~service:(service name) [txt name] ()
    ) |> List.join (txt ", ")
  in
  let content = [
    div [p (
      [txt "Please log in: ["] @ auth_systems @ [txt "]"]
    )]
  ] in
  base ~title:"Log in" ~content ()

let login_dummy ~state =
  let title, field_name, input_type =
    "Dummy login", "Username:", `Text
  in
  let form = post_form ~service:dummy_post
    (fun (nstate, name) ->
      [
        input ~input_type:`Hidden ~name:nstate ~value:state string;
        tablex [tbody [
          tr [
            th [label ~a:[a_label_for (Eliom_parameter.string_of_param_name name)] [txt field_name]];
            td [input ~input_type ~name string];
          ]]
        ];
        div [
          input ~input_type:`Submit ~value:"Login" string;
        ]
      ]) ()
  in
  let content = [
    form;
  ] in
  base ~title ~content ()

let login_password ~service ~allowsignups ~state =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let signup =
    if allowsignups then
      div [
          br ();
          txt "You can also ";
          a ~service:signup_captcha [txt "create an account"] service;
          txt ", or ";
          a ~service:changepw_captcha [txt "change your password"] service;
          txt " (if you forgot it, for example).";
        ]
    else txt ""
  in
  let form = post_form ~service:password_post
    (fun (lstate, (llogin, lpassword)) ->
      [
        input ~input_type:`Hidden ~name:lstate ~value:state string;
        tablex [tbody [
          tr [
            th [label ~a:[a_label_for (Eliom_parameter.string_of_param_name llogin)] [txt (s_ "Username:")]];
            td [input ~input_type:`Text ~name:llogin string];
          ];
          tr [
            th [label ~a:[a_label_for (Eliom_parameter.string_of_param_name lpassword)] [txt (s_ "Password:")]];
            td [input ~input_type:`Password ~name:lpassword string];
          ];
        ]];
        div [
          input ~input_type:`Submit ~value:(s_ "Login") string;
        ]
      ]) ()
  in
  let content = [
    form;
    signup;
  ] in
  base ~title:(s_ "Password login") ~content ()

let login_failed ~service () =
  let title = "Authentication failed" in
  let content =
    [
      div [txt "Authentication failed, probably because of a bad username or password, or you are not allowed to perform this operation."];
      div [
          txt "You can ";
          a ~service [txt "try to log in again"] ();
          txt ".";
        ];
    ]
  in
  base ~title ~content ()

let signup_captcha_img challenge =
  let src = make_uri ~service:signup_captcha_img challenge in
  img ~src ~alt:"CAPTCHA" ()

let format_captcha_error = function
  | None -> txt ""
  | Some x ->
     let msg = match x with
       | BadCaptcha -> "Bad security code!"
       | BadAddress -> "Bad e-mail address!"
     in
     div ~a:[a_style "color: red;"] [txt msg]

let signup_captcha ~service error challenge email =
  let form =
    post_form ~service:signup_captcha_post
      (fun (lchallenge, (lresponse, lemail)) ->
        [
          div [
              txt "E-mail address: ";
              input ~input_type:`Text ~name:lemail ~value:email string;
            ];
          div [
              input ~input_type:`Hidden ~name:lchallenge ~value:challenge string;
              txt "Please enter ";
              signup_captcha_img challenge;
              txt " in the following box: ";
              input ~input_type:`Text ~name:lresponse string;
            ];
          div [
              input ~input_type:`Submit ~value:"Submit" string;
            ];
        ]
      ) service
  in
  let error = format_captcha_error error in
  let content = [error; form] in
  base ~title:"Create an account" ~content ()

let signup_changepw ~service error challenge email username =
  let form =
    post_form ~service:changepw_captcha_post
      (fun (lchallenge, (lresponse, (lemail, lusername))) ->
        [
          div [
              txt "E-mail address: ";
              input ~input_type:`Text ~name:lemail ~value:email string;
              txt " or username: ";
              input ~input_type:`Text ~name:lusername ~value:username string;
              txt ".";
            ];
          div [
              input ~input_type:`Hidden ~name:lchallenge ~value:challenge string;
              txt "Please enter ";
              signup_captcha_img challenge;
              txt " in the following box: ";
              input ~input_type:`Text ~name:lresponse string;
            ];
          div [
              input ~input_type:`Submit ~value:"Submit" string;
            ];
        ]
      ) service
  in
  let error = format_captcha_error error in
  let content = [error; form] in
  base ~title:"Change password" ~content ()

let signup address error username =
  let error = match error with
    | None -> txt ""
    | Some e ->
       let msg = match e with
         | UsernameTaken -> "the username is already taken"
         | AddressTaken -> "there is already an account with this e-mail address"
         | BadUsername -> "the username is invalid"
         | BadPassword e -> Printf.sprintf "the password is too weak (%s)" e
         | PasswordMismatch -> "the two passwords are not the same"
         | BadSpaceInPassword -> "the password starts or ends with a space"
       in
       div [
           txt "The account creation ";
           span ~a:[a_style "color: red;"] [txt "failed"];
           txt " because ";
           txt msg;
           txt ". Please try again with a different one.";
         ]
  in
  let form =
    post_form ~service:signup_post
      (fun (lusername, (lpassword, lpassword2)) ->
        [
          div [
              txt "Your e-mail address is: ";
              txt address;
              txt ".";
            ];
          div [
              txt "Please choose a username: ";
              input ~input_type:`Text ~name:lusername ~value:username string;
              txt " and a password: ";
              input ~input_type:`Password ~name:lpassword string;
              txt ".";
            ];
          div[
              txt "Type the password again: ";
              input ~input_type:`Password ~name:lpassword2 string;
              txt ".";
            ];
          div [
              input ~input_type:`Submit ~value:"Submit" string;
            ];
        ]
      ) ()
  in
  let content = [error; form] in
  base ~title:"Create an account" ~content ()

let changepw ~username ~address error =
  let error = match error with
    | None -> txt ""
    | Some e ->
       let reason = match e with
         | PasswordMismatch -> "the two passwords are not the same"
         | BadPassword e -> Printf.sprintf "the new password is too weak (%s)" e
         | BadSpaceInPassword -> "the new password starts or ends with a space"
         | _ -> " of an unknown reason"
       in
       div [
           txt "The change ";
           span ~a:[a_style "color: red;"] [txt "failed"];
           txt " because ";
           txt reason;
           txt ". Please try again with a different one.";
         ]
  in
  let form =
    post_form ~service:changepw_post
      (fun (lpassword, lpassword2) ->
        [
          div [
              txt "Your username is: ";
              txt username;
              txt " and your e-mail address is: ";
              txt address;
              txt ".";
            ];
          div [
              txt "Please choose a password: ";
              input ~input_type:`Password ~name:lpassword string;
              txt ".";
            ];
          div [
              txt "Type the password again: ";
              input ~input_type:`Password ~name:lpassword2 string;
              txt ".";
            ];
          div [
              input ~input_type:`Submit ~value:"Submit" string;
            ];
        ]
      ) ()
  in
  let content = [error; form] in
  base ~title:"Change password" ~content ()

let booth () =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let head = head (title (txt (s_ "Belenios Booth"))) [
    link ~rel:[`Stylesheet] ~href:(static "booth.css") ();
    script ~a:[a_src (static "tool_js_booth.js")] (txt "");
  ] in
  let wait_div =
    div ~a:[a_id "wait_div"] [
        txt "Please wait... ";
        img ~src:(static "encrypting.gif") ~alt:"Loading..." ();
      ]
  in
  let election_loader =
    div ~a:[a_id "election_loader"; a_style "display:none;"] [
      h1 [txt (s_ "Belenios Booth")];
      br ();
      txt "Load an election on this server by giving its UUID:";
      div [unsafe_textarea "uuid" ""];
      div [button_no_value ~button_type:`Button ~a:[a_id "load_uuid"] [txt "Load from UUID"]];
      br ();
      txt "Load any election by giving its parameters:";
      div [unsafe_textarea "election_params" ""];
      div [button_no_value ~button_type:`Button ~a:[a_id "load_params"] [txt "Load parameters"]];
    ]
  in
  let text_choices = unsafe_textarea "choices" "" in
  let ballot_form =
    post_form ~a:[a_id "ballot_form"] ~service:election_submit_ballot
      (fun encrypted_vote -> [
        div ~a:[a_id "div_ballot"; a_style "display:none;"] [
          txt "Encrypted ballot:";
          div [
            textarea
              ~a:[a_id "ballot"; a_rows 1; a_cols 80; a_readonly ()]
              ~name:encrypted_vote ();
          ];
        ];
        p [
          txt (s_ "Your ballot has been successfully encrypted, ");
          b [txt (s_ "but has not been cast yet")];
          txt (s_ "!");
        ];
        p [
          txt (s_ "Your smart ballot tracker is ");
          span ~a:[a_id "ballot_tracker"] [];
        ];
        p [
          txt (s_ "We invite you to save it in order to check later that it is taken into account.");
        ];
        br ();
        div ~a:[a_id "div_submit"] [
            input ~input_type:`Submit ~value:(s_ "Continue") ~a:[a_style "font-size:30px;"] string;
          ];
        div ~a:[a_id "div_submit_manually"; a_style "display:none;"] [
            txt "You must submit your ballot manually.";
          ];
        br (); br ();
       ])
      ()
  in
  let main =
    div ~a:[a_id "main"] [
      div ~a:[a_style "text-align:center; margin-bottom:20px;"] [
        span ~a:[a_id "progress1"; a_style "font-weight:bold;"] [txt (s_ "Input credential")];
        txt " — ";
        span ~a:[a_id "progress2"] [txt (s_ "Answer to questions")];
        txt " — ";
        span ~a:[a_id "progress3"] [txt (s_ "Review and encrypt")];
        txt " — ";
        span ~a:[a_id "progress4"] [txt (s_ "Authenticate")];
        txt " — ";
        span ~a:[a_id "progress5"] [txt (s_ "Confirm")];
        txt " — ";
        span ~a:[a_id "progress6"] [txt (s_ "Done")];
        hr ();
      ];
      div ~a:[a_id "intro"; a_style "text-align:center;"] [
        div ~a:[a_class ["current_step"]] [
          txt (s_ "Step 1/6: Input credential");
        ];
        br (); br ();
        p ~a:[a_id "input_code"; a_style "font-size:20px;"] [
          txt (s_ "Input your credential ");
        ];
        br (); br ();
      ];
      div ~a:[a_id "question_div"; a_style "display:none;"] [
        div ~a:[a_class ["current_step"]] [
          txt (s_ "Step 2/6: Answer to questions");
        ];
      ];
      div ~a:[a_id "plaintext_div"; a_style "display:none;"] [
        div ~a:[a_class ["current_step"]] [
          txt (s_ "Step 3/6: Review and encrypt");
        ];
        div ~a:[a_id "pretty_choices"] [];
        div ~a:[a_style "display:none;"] [
          txt "Plaintext raw ballot:";
          div [text_choices];
        ];
        div ~a:[a_style "text-align:center;"] [
          div ~a:[a_id "encrypting_div"] [
            p [txt (s_ "Please wait while your ballot is being encrypted...")];
            img ~src:(static "encrypting.gif") ~alt:(s_ "Encrypting...") ();
          ];
          div ~a:[a_id "ballot_div"; a_style "display:none;"] [ballot_form];
          Unsafe.data ("<button onclick=\"location.reload();\">" ^ s_ "Restart" ^ "</button>");
          br (); br ();
        ];
      ];
    ]
  in
  let booth_div =
    div ~a:[a_id "booth_div"; a_style "display:none;"] [
      div ~a:[a_id "header"] [
        div ~a:[a_style "float: left; padding: 15px;"] [
          img ~alt:(s_ "Election server") ~a:[a_height 70]
            ~src:(static "logo.png") ();
        ];
        div ~a:[a_style "float: right; padding: 15px;"] [
          img ~alt:"" ~a:[a_height 70]
            ~src:(static "placeholder.png") ();
        ];
        div ~a:[a_style "text-align:center; padding: 20px;"] [
          h1 ~a:[a_id "election_name"] [];
          p ~a:[a_id "election_description"] [];
        ];
        div ~a:[a_style "clear: both;"] [];
      ];
      main;
      div ~a:[a_id "footer"] [
        div ~a:[a_id "bottom"] [
          div [
            txt (s_ "Election UUID: ");
            span ~a:[a_id "election_uuid"] [];
          ];
          div [
            txt (s_ "Election fingerprint: ");
            span ~a:[a_id "election_fingerprint"] [];
          ];
        ];
      ];
    ]
  in
  let body = body [
    wait_div;
    election_loader;
    div ~a:[a_id "wrapper"] [
      booth_div;
    ];
  ] in
  return @@ html ~a:[a_dir `Ltr; a_xml_lang lang] head body

let booth_2 () =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let head = head (title (txt (s_ "Belenios Booth"))) [
    link ~rel:[`Stylesheet] ~href:(static "booth.css") ();
    script ~a:[a_src (static "tool_js_booth.js")] (txt "");
  ] in
  let wait_div =
    div ~a:[a_id "wait_div"] [
        txt "Please wait... ";
        img ~src:(static "encrypting.gif") ~alt:"Loading..." ();
      ]
  in
  let election_loader =
    div ~a:[a_id "election_loader"; a_style "display:none;"] [
      h1 [txt (s_ "Belenios Booth")];
      br ();
      txt "Load an election on this server by giving its UUID:";
      div [unsafe_textarea "uuid" ""];
      div [button_no_value ~button_type:`Button ~a:[a_id "load_uuid"] [txt "Load from UUID"]];
      br ();
      txt "Load any election by giving its parameters:";
      div [unsafe_textarea "election_params" ""];
      div [button_no_value ~button_type:`Button ~a:[a_id "load_params"] [txt "Load parameters"]];
    ]
  in
  let text_choices = unsafe_textarea "choices" "" in
  let ballot_form =
    post_form ~a:[a_id "ballot_form"] ~service:election_submit_ballot
      (fun encrypted_vote -> [
        div ~a:[a_id "div_ballot"; a_style "display:none;"] [
          txt "Encrypted ballot:";
          div [
            textarea
              ~a:[a_id "ballot"; a_rows 1; a_cols 80; a_readonly ()]
              ~name:encrypted_vote ();
          ];
        ];
        p [
          txt (s_ "Your ballot has been successfully encrypted, ");
          b [txt (s_ "but has not been cast yet")];
          txt (s_ "!");
        ];
        p [
          txt (s_ "Your smart ballot tracker is ");
          span ~a:[a_id "ballot_tracker"] [];
        ];
        p [
          txt (s_ "We invite you to save it in order to check later that it is taken into account.");
        ];
        br ();
        div ~a:[a_id "div_submit"] [
            input ~input_type:`Submit ~value:(s_ "Continue") ~a:[a_style "font-size:30px;"] string;
          ];
        div ~a:[a_id "div_submit_manually"; a_style "display:none;"] [
            txt "You must submit your ballot manually.";
          ];
        br (); br ();
       ])
      ()
  in
  let main =
    div ~a:[a_id "main"] [
      div ~a:[a_style "text-align:center; margin-bottom:20px;"] [
        span ~a:[a_id "progress1"; a_style "font-weight:bold;"] [txt (s_ "Input credential")];
        txt " — ";
        span ~a:[a_id "progress2"] [txt (s_ "Answer to questions")];
        txt " — ";
        span ~a:[a_id "progress3"] [txt (s_ "Review and encrypt")];
        txt " — ";
        span ~a:[a_id "progress4"] [txt (s_ "Authenticate")];
        txt " — ";
        span ~a:[a_id "progress5"] [txt (s_ "Confirm")];
        txt " — ";
        span ~a:[a_id "progress6"] [txt (s_ "Done")];
        hr ();
      ];
      h1 [txt ("DO NOT CAST YOUR VOTE HERE, THIS IS A WORK IN PROGRESS PAGE")];
      div ~a:[a_id "intro"; a_style "text-align:center;"] [
        div ~a:[a_class ["current_step"]] [
          txt (s_ "Step 1/6: Input credential");
        ];
        div ~a:[a_id "language-selector-container"] [];
        div ~a:[a_id "like_button_container"] [];
        div ~a:[a_id "translated_like_button_container"] [];
        div ~a:[a_id "i18n-output"] [];
        br (); br ();
        p ~a:[a_id "input_code"; a_style "font-size:20px;"] [
          txt (s_ "Input your credential ");
        ];
        br (); br ();
      ];
      div ~a:[a_id "question_div"; a_style "display:none;"] [
        div ~a:[a_class ["current_step"]] [
          txt (s_ "Step 2/6: Answer to questions");
        ];
      ];
      div ~a:[a_id "plaintext_div"; a_style "display:none;"] [
        div ~a:[a_class ["current_step"]] [
          txt (s_ "Step 3/6: Review and encrypt");
        ];
        div ~a:[a_id "pretty_choices"] [];
        div ~a:[a_style "display:none;"] [
          txt "Plaintext raw ballot:";
          div [text_choices];
        ];
        div ~a:[a_style "text-align:center;"] [
          div ~a:[a_id "encrypting_div"] [
            p [txt (s_ "Please wait while your ballot is being encrypted...")];
            img ~src:(static "encrypting.gif") ~alt:(s_ "Encrypting...") ();
          ];
          div ~a:[a_id "ballot_div"; a_style "display:none;"] [ballot_form];
          Unsafe.data ("<button onclick=\"location.reload();\">" ^ s_ "Restart" ^ "</button>");
          br (); br ();
        ];
      ];
    ]
  in
  let booth_div =
    div ~a:[a_id "booth_div"; a_style "display:none;"] [
      div ~a:[a_id "header"] [
        div ~a:[a_style "float: left; padding: 15px;"] [
          img ~alt:(s_ "Election server") ~a:[a_height 70]
            ~src:(static "logo.png") ();
        ];
        div ~a:[a_style "float: right; padding: 15px;"] [
          img ~alt:"" ~a:[a_height 70]
            ~src:(static "placeholder.png") ();
        ];
        div ~a:[a_style "text-align:center; padding: 20px;"] [
          h1 ~a:[a_id "election_name"] [];
          p ~a:[a_id "election_description"] [];
        ];
        div ~a:[a_style "clear: both;"] [];
      ];
      main;
      div ~a:[a_id "footer"] [
        div ~a:[a_id "bottom"] [
          div [
            txt (s_ "Election UUID: ");
            span ~a:[a_id "election_uuid"] [];
          ];
          div [
            txt (s_ "Election fingerprint: ");
            span ~a:[a_id "election_fingerprint"] [];
          ];
        ];
      ];
    ]
  in
  let open Belenios_version in
  let javascript_mode = if debug then "development" else "production" in
  let javascript_extension = if debug then "" else ".min" in
  let external_javascript_folder = "node_modules" in
  let internal_javascript_folder = "internal_modules" in
  let react_js_url = external_javascript_folder ^ "/react/umd/react." ^ javascript_mode ^ javascript_extension ^ ".js" in
  let react_dom_js_url = external_javascript_folder ^ "/react-dom/umd/react-dom." ^ javascript_mode ^ javascript_extension ^ ".js" in
  let i18next_js_url = external_javascript_folder ^ "/i18next/dist/umd/i18next" ^ javascript_extension ^ ".js" in
  let react_i18next_js_url = external_javascript_folder ^ "/react-i18next/dist/umd/react-i18next" ^ javascript_extension ^ ".js" in
  let react_i18next_http_backend_js_url = external_javascript_folder ^ "/i18next-http-backend/i18nextHttpBackend" ^ javascript_extension ^ ".js" in
  let i18n_init_js_url = internal_javascript_folder ^ "/booth/js/i18n_init.js" in
  let shortcuts_js_url = internal_javascript_folder ^ "/booth/js/shortcuts.js" in
  let like_button_js_url = internal_javascript_folder ^ "/booth/js/like_button.js" in
  let translated_like_button_js_url = internal_javascript_folder ^ "/booth/js/translated_like_button.js" in
  let app_js_url = internal_javascript_folder ^ "/booth/js/app.js" in
  let body = body [
    wait_div;
    election_loader;
    div ~a:[a_id "wrapper"] [
      booth_div;
    ];
    script ~a:[a_src (static react_js_url)] (txt "");
    script ~a:[a_src (static react_dom_js_url)] (txt "");
    script ~a:[a_src (static i18next_js_url)] (txt "");
    script ~a:[a_src (static react_i18next_js_url)] (txt "");
    script ~a:[a_src (static react_i18next_http_backend_js_url)] (txt "");
    script ~a:[a_src (static i18n_init_js_url)] (txt "");
    script ~a:[a_src (static shortcuts_js_url)] (txt "");
    script ~a:[a_src (static like_button_js_url)] (txt "");
    script ~a:[a_src (static translated_like_button_js_url)] (txt "");
    script ~a:[a_src (static app_js_url)] (txt "");
  ] in
  return @@ html ~a:[a_dir `Ltr; a_xml_lang lang] head body

let schulze q r =
  let%lwt l = Web_i18n.get_preferred_gettext () in
  let open (val l) in
  let title = s_ "Schulze method" in
  let explicit_winners =
    List.map
      (List.map
         (fun i -> q.Question_nh_t.q_answers.(i))
      ) r.schulze_winners
  in
  let pretty_winners =
    List.map
      (fun l ->
        li [match l with
            | [] -> failwith "anomaly in Web_templates.schulze"
            | [x] -> txt x
            | l -> div [
                       txt (s_ "Tie:");
                       ul (List.map (fun x -> li [txt x]) l);
                     ]
          ]
      ) explicit_winners
  in
  let content =
    [
      txt (s_ "The Schulze winners are:");
      ol pretty_winners;
    ]
  in
  base ~title ~content ()
