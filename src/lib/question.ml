(**************************************************************************)
(*                                BELENIOS                                *)
(*                                                                        *)
(*  Copyright © 2012-2019 Inria                                           *)
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

open Signatures_core
open Serializable_core_t

type question = Question_std_t.question

let read_question = Question_std_j.read_question
let write_question = Question_std_j.write_question

module type S = sig
  type elt
  type 'a m

  val create_answer : question -> public_key:elt -> prefix:string -> int array -> Yojson.Safe.json m
  val verify_answer : question -> public_key:elt -> prefix:string -> Yojson.Safe.json -> bool

  val extract_ciphertexts : Yojson.Safe.json -> elt ciphertext array
end

module Make (M : RANDOM) (G : GROUP) = struct
  type elt = G.t
  type 'a m = 'a M.t
  let ( >>= ) = M.bind
  module Q = Question_std.Make (M) (G)

  let create_answer q ~public_key ~prefix m =
    Q.create_answer q ~public_key ~prefix m >>= fun answer ->
    answer
    |> Question_std_j.string_of_answer G.write
    |> Yojson.Safe.from_string
    |> M.return

  let verify_answer q ~public_key ~prefix a =
    a
    |> Yojson.Safe.to_string
    |> Question_std_j.answer_of_string G.read
    |> Q.verify_answer q ~public_key ~prefix

  let extract_ciphertexts a =
    a
    |> Yojson.Safe.to_string
    |> Question_std_j.answer_of_string G.read
    |> Q.extract_ciphertexts
end