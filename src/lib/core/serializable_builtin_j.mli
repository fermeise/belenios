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

open Signatures_core
open Serializable_builtin_t

(** {1 Serializers for type number} *)

val write_number : number writer
val read_number : number reader

(** {1 Serializers for type uuid} *)

val write_uuid : uuid writer
val read_uuid : uuid reader

(** {1 Serializers for type hash} *)

val write_hash : hash writer
val read_hash : hash reader

(** {1 Serializers for type shape} *)

val write_shape : 'a writer -> 'a shape writer
val read_shape : 'a reader -> 'a shape reader

(** {1 Serializers for type weight} *)

val write_weight : weight writer
val read_weight : weight reader

(** {1 Serializers for type question_result} *)

val write_question_result : question_result writer
val read_question_result : question_result reader
