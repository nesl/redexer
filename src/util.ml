(*
 * Copyright (c) 2010-2014,
 *  Jinseong Jeon <jsjeon@cs.umd.edu>
 *  Kris Micinski <micinski@cs.umd.edu>
 *  Jeff Foster   <jfoster@cs.umd.edu>
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * 3. The names of the contributors may not be used to endorse or promote
 * products derived from this software without specific prior written
 * permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *)

(***********************************************************************)
(* Utilities                                                           *)
(***********************************************************************)

module S = String
module L = List

module RE = Str

module IntKey =
struct
  type t = int
  let compare = Pervasives.compare
end

module IS = Set.Make(IntKey)

module IM = Map.Make(IntKey)

(* read_lines : in_channel -> string list *)
let read_lines ch : string list =
  let rec aux acc =
    try
      let line = input_line ch in
      aux (line :: acc)
    with End_of_file -> L.rev acc
  in aux []

(***********************************************************************)
(* a few list utilities                                                *)
(***********************************************************************)

(* range : int -> int -> int list -> int list *)
let rec range (x: int) (y: int) res : int list =
  if y < x then res else
    let new_res = y :: res in
    if x = y then new_res else range x (y-1) new_res

(* repeat : 'a -> int -> 'a list -> 'a list *)
let rec repeat (x: 'a) (n: int) res : 'a list =
  if n <= 0 then res else repeat x (n - 1) (x :: res)

(* get_last : 'a list -> 'a *)
let get_last (l: 'a list) : 'a =
  L.hd (L.rev l)

(* rm_last : 'a list -> 'a list *)
let rm_last (l: 'a list) : 'a list =
  L.rev (L.tl (L.rev l))

(***********************************************************************)
(* a few string utilities                                              *)
(***********************************************************************)

(* trim_1st : string -> string *)
let trim_1st str : string =
  let len = S.length str in
  if len <= 0 then str else S.sub str 1 (len - 1)

(* trim_last : string -> string *)
let trim_last str : string =
  let len = S.length str in
  if len <= 0 then str else S.sub str 0 (len - 1)

(* explode : string -> char list *)
let explode s =
  let rec expl i l =
    if i < 0 then l else
      expl (i - 1) (s.[i] :: l) in
  expl (S.length s - 1) []
    
let implode l =
  let result = S.create (L.length l) in
  let rec imp i = function
    | [] -> result
    | c :: l -> result.[i] <- c; imp (i + 1) l in
  imp 0 l

(* str_rev : string -> string *)
let str_rev s =
  implode (L.rev (explode s))

(* split_string : string -> char -> string list *)
let split_string str (split: char) : string list =
  let rec helper (str: char list) (cur_accum: char list) accums : string list =
    match str with
    | [] ->
      if L.length cur_accum > 0 then
        L.rev ((implode (L.rev cur_accum))::accums)
      else
        L.rev accums
    | hd::tl -> 
      if hd = split then
      (
        if cur_accum <> [] then
          helper tl [] ((implode (L.rev cur_accum))::accums)
        else
          helper tl [] accums
      )
      else
        helper tl (hd::cur_accum) accums
  in
  helper (explode str) [] []

(* begins_with : string -> string -> bool *)
let begins_with (str: string) (prefix: string) : bool =
  let rec h a b =
    match a with
    | hd :: tl ->
    (
      match b with
      | hd' :: tl' -> if hd' = hd then h tl tl' else false
      | [] -> true
    )
    | _ -> false
  in
  h (explode str) (explode prefix)

(* ends_with : string -> string -> bool *)
let ends_with (str: string) (suffix: string) : bool =
  begins_with (str_rev str) (str_rev suffix)

(* contains : string -> string -> bool *)
let contains (str: string) (sub: string) : bool =
  let re = RE.regexp_string sub in
  try ignore (RE.search_forward re str 0); true
  with Not_found -> false

