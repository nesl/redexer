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
(* Callgraph                                                           *)
(***********************************************************************)

module St = Stats
module DA = DynArray

module U  = Util
module IM = U.IM

module I = Instr
module D = Dex
module J = Java
module V = Visitor

module Adr = Android
module App = Adr.App
module Con = Adr.Content
module Ads = Adr.Ads

module P = Propagation

module L = List
module H = Hashtbl
module S = String

module Pf = Printf

(***********************************************************************)
(* Basic Types/Elements                                                *)
(***********************************************************************)

module IS = Set.Make(D.IdxKey)

type clzz = {
  c_idx : D.link;
  mutable c_mtd : IS.t;
}

type meth = {
  m_idx : D.link;
  mutable m_succs : IS.t; (* its callees; whom does this call? *)
  mutable m_preds : IS.t; (* its callers; who invokes this? *)
}

type cg = {
  clzz_h : (D.link, clzz) H.t;
  meth_h : (D.link, meth) H.t;
}

(***********************************************************************)
(* Utilities                                                           *)
(***********************************************************************)

let pp = Printf.printf

let (@@) l1 l2 = L.rev_append (L.rev l1) l2

let trim_bracket s : string =
  let len = S.length s in
  if S.get s 0 = '<' && S.get s (len-1) = '>'
  then S.sub s 1 (len-2) else s

let get_mtd_name (dx: D.dex) (mid: D.link) =
  trim_bracket (D.get_mtd_name dx mid)

let trim_semicolon s : string =
  let len = S.length s in
  if S.get s (len-1) = ';'
  then S.sub s 0 (len-1) else s

let get_cls_name (dx: D.dex) (cid: D.link) =
  trim_semicolon (D.get_ty_str dx cid)

let find_class cg (cid: D.link) : clzz =
  H.find cg.clzz_h cid

let find_method cg (mid: D.link) : meth =
  H.find cg.meth_h mid

let find_or_new_method (dx: D.dex) cg (mid: D.link) : meth * bool =
  let cid = D.get_cid_from_mid dx mid in
  let clz =
    try find_class cg cid
    with Not_found ->
      let nod = {
        c_idx = cid;
        c_mtd = IS.empty;
      } in
      H.add cg.clzz_h cid nod; nod
  in
  clz.c_mtd <- IS.add mid clz.c_mtd;
  try find_method cg mid, false
  with Not_found ->
    let nod = {
      m_idx = mid;
      m_succs = IS.empty;
      m_preds = IS.empty;
    } in
    H.add cg.meth_h mid nod; nod, true

(* add_call : D.dex -> cg -> D.link -> D.link -> bool *)
let add_call (dx: D.dex) cg (caller: D.link) (callee: D.link) : bool =
  let caller_n, changed_r = find_or_new_method dx cg caller
  and callee_n, changed_e = find_or_new_method dx cg callee
  in
  caller_n.m_succs <- IS.add callee caller_n.m_succs;
  callee_n.m_preds <- IS.add caller callee_n.m_preds;
  changed_r || changed_e

(***********************************************************************)
(* Call Graph                                                          *)
(***********************************************************************)

let cg = {
  clzz_h = H.create 31;
  meth_h = H.create 153;
}

(**
  given instruction, add an edge from caller to callee, if exists,
  and return the callee id so as to visit it incrementally
*)
let interpret_ins (dx: D.dex) (caller: D.link) (ins: D.link) : D.link =
  if not (D.is_ins dx ins) then D.no_idx else
  let op, opr = D.get_ins dx ins in
  match I.access_link op with
  | I.METHOD_IDS ->
    (* last opr at invoke-kind must be method id *)
    let callee = D.opr2idx (U.get_last opr) in
    let cid = D.get_cid_from_mid dx callee in
    let cname = D.get_ty_str dx cid
    and mname = D.get_mtd_name dx callee in
(*
    (* Component transition *)
    if 0 = S.compare mname Con.start_act
    || 0 = S.compare mname Con.start_srv then
*)
    (* Intent creation *)
    if 0 = S.compare mname J.init
    && 0 = S.compare cname (J.to_java_ty Con.intent) then
    (
      let cid = D.get_cid_from_mid dx caller in
      let _, citm = D.get_citm dx cid caller in
      let dfa = St.time "const" (P.make_dfa dx) citm in
      let module DFA = (val dfa: Dataflow.ANALYSIS
        with type st = D.link and type l = (P.value IM.t))
      in
      St.time "const" DFA.fixed_pt ();
      let out = St.time "const" DFA.out ins
(*
      (* invoke-virtual v_this, v_intent, @mid *)
      and reg = U.get_last (U.rm_last opr) in
*)
      (* invoke-direct v_intent, ... *)
      and reg = L.hd opr in
      match IM.find (I.of_reg reg) out with
      | P.Intent i when D.no_idx <> D.get_cid dx i ->
      (
        let act_cid = D.get_cid dx i in
        let mids = Adr.find_lifecycle_act dx act_cid in
        if [] = mids then D.no_idx else
          let callee = L.hd mids in
          if add_call dx cg caller callee then callee else D.no_idx
      )
      | _ -> D.no_idx
    )
    else (* explicit call relations *)
      if add_call dx cg caller callee then callee else D.no_idx
  | _ -> D.no_idx

class cg_maker (dx: D.dex) =
object
  inherit V.iterator dx

  method v_cdef (cdef: D.class_def_item) : unit =
    let cname = J.of_java_ty (D.get_ty_str dx cdef.D.c_class_id) in
    skip_cls <- Adr.is_static_library cname || Ads.is_ads_pkg cname

  val mutable caller = D.no_idx
  method v_emtd (emtd: D.encoded_method) : unit =
    caller <- emtd.D.method_idx

  method v_ins (ins: D.link) : unit =
    ignore (interpret_ins dx caller ins)

end

(* make_cg : D.dex -> cg *)
let make_cg (dx: D.dex) : cg =
  H.clear cg.clzz_h; H.clear cg.meth_h;
  V.iter (new cg_maker dx);
  let iter i (mit: D.method_id_item) =
    let cid = mit.D.m_class_id
    and mid = D.to_idx i in
    let sid = D.get_supermethod dx cid mid in
    if sid <> D.no_idx then
      (* implicit super() call relations *)
      ignore (add_call dx cg mid sid)
  in
  (* visitor see only impl methods; rather, see ids directly *)
  DA.iteri iter dx.D.d_method_ids;
  cg

(* make_partial_cg : D.dex -> int -> D.link list -> cg *)
let make_partial_cg (dx: D.dex) depth (cids: D.link list) : cg =
  H.clear cg.clzz_h; H.clear cg.meth_h;
  let worklist = ref IS.empty
  and iter_cnt = ref 0 in
  let v_method (mid: D.link) : unit =
    let v_ins (ins: D.link) =
      let callee = interpret_ins dx mid ins in
      if callee <> D.no_idx then
        worklist := IS.add callee !worklist
    in
    let cid = D.get_cid_from_mid dx mid in
    let sid = D.get_supermethod dx cid mid in
    (
      (* implicit super() call relations *)
      if sid <> D.no_idx && add_call dx cg mid sid then
        worklist := IS.add sid !worklist
    );
    try
      let _, citm = D.get_citm dx cid mid in
      DA.iter v_ins citm.D.insns
    with D.Wrong_dex _ -> ()
  in
  let init_worklist acc (cid: D.link) =
    let mids, _ = L.split (D.get_mtds dx cid) in
    L.fold_left (fun acc' mid -> IS.add mid acc') acc mids
  in
  worklist := L.fold_left init_worklist IS.empty cids;
  while !iter_cnt < depth && not (IS.is_empty !worklist) do
    incr iter_cnt;
    let mids = IS.elements !worklist in
    worklist := IS.empty;
    L.iter v_method mids
  done;
  cg

(***********************************************************************)
(* Call Chain                                                          *)
(***********************************************************************)

(**
  m1 -> m4; m2 -> m4; m3 -> m5;
       m4 -> m6;      m5 -> m6;

  callers... m6 = [ [m6; m4; m1]; [m6; m4; m2]; [m6; m5; m3] ]
*)

type cc = D.link list

(* callers : D.dex -> int -> cg -> D.link -> cc list *)
let rec callers (dx: D.dex) depth cg (mid: D.link) : cc list =
  if depth <= 0 then [[]] else
  let node, _ = find_or_new_method dx cg mid in
  let pred = IS.elements node.m_preds in
  if pred = [] then [[mid]] else
    let call_chains = L.rev_map (callers dx (depth-1) cg) pred in
    L.rev_map (fun cc -> mid :: cc) (L.flatten call_chains)

(* dependants : D.dex -> cg -> D.link -> D.link list *)
let dependants (dx: D.dex) cg (cid: D.link) : D.link list =
  let mtds = D.get_mtds dx cid
  and mapper (mid, _) =
    let mids = L.flatten (callers dx 9 cg mid) in
    L.rev_map (D.get_cid_from_mid dx) mids
  in
  let cids = L.flatten (L.rev_map mapper mtds) in
  IS.elements (L.fold_left (fun acc id -> IS.add id acc) IS.empty cids)

(***********************************************************************)
(* DOTtify                                                             *)
(***********************************************************************)

(* cg2dot : D.dex -> cg -> unit *)
let cg2dot (dx: D.dex) cg : unit =
  pp "digraph callgraph {\n";
  pp "  rankdir=LR\n";
  pp "  node [shape=record]\n";
  let each_clzz _ c =
    pp "  c%d [label=\"%s | " (D.of_idx c.c_idx) (get_cls_name dx c.c_idx);
    let rec dot_list = function
      | [] -> ()
      | [mid] ->
        pp "<m%d> %s\"]\n" (D.of_idx mid) (get_mtd_name dx mid)
      | h::tl ->
        pp "<m%d> %s | " (D.of_idx h) (get_mtd_name dx h); dot_list tl
    in
    dot_list (IS.elements c.c_mtd)
  in
  H.iter each_clzz cg.clzz_h;
  let dot_call _ m =
    let each_callee callee_idx =
      let midx1  = D.of_idx m.m_idx in
      let caller = D.get_mit dx m.m_idx in
      let cidx1  = D.of_idx caller.D.m_class_id in
      let midx2  = D.of_idx callee_idx in
      let callee = D.get_mit dx callee_idx in
      let cidx2  = D.of_idx callee.D.m_class_id in
      pp "  c%d:m%d -> c%d:m%d\n" cidx1 midx1 cidx2 midx2
    in
    IS.iter each_callee m.m_succs
  in
  H.iter dot_call cg.meth_h;
  pp "}\n"

