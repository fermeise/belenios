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

open Belenios_platform
open Platform
open Common

type number = Z.t
type uuid

val min_uuid_length : int

val uuid_of_raw_string : string -> uuid
val raw_string_of_uuid : uuid -> string

type 'a shape = 'a Shape.t =
  | SAtomic of 'a
  | SArray of 'a shape array

module Weight : sig
  type t
  val zero : t
  val one : t
  val two : t
  val max_weight : t
  val compare : t -> t -> int
  val ( + ) : t -> t -> t
  val ( / ) : t -> t -> t
  val ( mod ) : t -> t -> t
  val min : t -> t -> t
  val max : t -> t -> t
  val of_string : string -> t
  val to_string : t -> string
  val of_int : int -> t
  val to_int : t -> int (* FIXME: weights can be bigger than int *)
end

type weight = Weight.t

val weight_of_json : Yojson.Safe.t -> weight
val json_of_weight : weight -> Yojson.Safe.t

(** Input: [str = "something[,weight]"]
    Output:
    - if [weight] is an integer > 0, return [(something, weight)]
    - else, return [(str, 1)] *)
val extract_weight : string -> string * Weight.t

val split_identity : string -> string * string * Weight.t
val split_identity_opt : string -> string * string option * Weight.t option
