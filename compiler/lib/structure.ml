open Stdlib
open Code

let get_edges g src = try Hashtbl.find g src with Not_found -> Addr.Set.empty

let add_edge g src dst = Hashtbl.replace g src (Addr.Set.add dst (get_edges g src))

let reverse_tree t =
  let g = Hashtbl.create 16 in
  Hashtbl.iter (fun child parent -> add_edge g parent child) t;
  g

let reverse_graph g =
  let g' = Hashtbl.create 16 in
  Hashtbl.iter
    (fun child parents -> Addr.Set.iter (fun parent -> add_edge g' parent child) parents)
    g;
  g'

type graph = (Addr.t, Addr.Set.t) Hashtbl.t

type t =
  { succs : (Addr.t, Addr.Set.t) Hashtbl.t
  ; preds : (Addr.t, Addr.Set.t) Hashtbl.t
  ; reverse_post_order : Addr.t list
  ; block_order : (Addr.t, int) Hashtbl.t
  }

let get_nodes g =
  List.fold_left
    ~init:Addr.Set.empty
    ~f:(fun s pc -> Addr.Set.add pc s)
    g.reverse_post_order

let block_order g pc = Hashtbl.find g.block_order pc

let is_backward g pc pc' = Hashtbl.find g.block_order pc >= Hashtbl.find g.block_order pc'

let is_forward g pc pc' = Hashtbl.find g.block_order pc < Hashtbl.find g.block_order pc'

(* pc has at least two forward edges moving into it *)
let is_merge_node' block_order preds pc =
  let s = try Hashtbl.find preds pc with Not_found -> Addr.Set.empty in
  let o = Hashtbl.find block_order pc in
  let n =
    Addr.Set.fold (fun pc' n -> if Hashtbl.find block_order pc' < o then n + 1 else n) s 0
  in
  n > 1

let rec leave_try_body block_order preds blocks pc =
  if is_merge_node' block_order preds pc
  then false
  else
    match Addr.Map.find pc blocks with
    | { body = []; branch = (Return _ | Stop), _; _ } -> false
    | { body = []; branch = Branch (pc', _), _; _ } ->
        leave_try_body block_order preds blocks pc'
    | _ -> true

let build_graph blocks pc =
  let succs = Hashtbl.create 16 in
  let l = ref [] in
  let visited = Hashtbl.create 16 in
  let poptraps = ref [] in
  let rec traverse ~englobing_exn_handlers pc =
    if not (Hashtbl.mem visited pc)
    then (
      Hashtbl.add visited pc ();
      let successors = Code.fold_children blocks pc Addr.Set.add Addr.Set.empty in
      Hashtbl.add succs pc successors;
      let block = Addr.Map.find pc blocks in
      Addr.Set.iter
        (fun pc' ->
          let englobing_exn_handlers =
            match fst block.branch with
            | Pushtrap ((body_pc, _), _, _, _) when pc' = body_pc ->
                pc :: englobing_exn_handlers
            | Poptrap (leave_pc, _) -> (
                match englobing_exn_handlers with
                | [] -> assert false
                | enter_pc :: rem ->
                    poptraps := (enter_pc, leave_pc) :: !poptraps;
                    rem)
            | _ -> englobing_exn_handlers
          in
          traverse ~englobing_exn_handlers pc')
        successors;
      l := pc :: !l)
  in
  traverse ~englobing_exn_handlers:[] pc;
  let block_order = Hashtbl.create 16 in
  List.iteri !l ~f:(fun i pc -> Hashtbl.add block_order pc i);
  let preds = reverse_graph succs in
  List.iter !poptraps ~f:(fun (enter_pc, leave_pc) ->
      if leave_try_body block_order preds blocks leave_pc
      then (
        (* Add an edge to limit the [try] body *)
        Hashtbl.add succs enter_pc (Addr.Set.add leave_pc (Hashtbl.find succs enter_pc));
        Hashtbl.add preds leave_pc (Addr.Set.add enter_pc (Hashtbl.find preds leave_pc))));
  { succs; preds; reverse_post_order = !l; block_order }

let dominator_tree g =
  (* A Simple, Fast Dominance Algorithm
     Keith D. Cooper, Timothy J. Harvey, and Ken Kennedy *)
  let dom = Hashtbl.create 16 in
  let rec inter pc pc' =
    (* Compute closest common ancestor *)
    if pc = pc'
    then pc
    else if is_forward g pc pc'
    then inter pc (Hashtbl.find dom pc')
    else inter (Hashtbl.find dom pc) pc'
  in
  List.iter g.reverse_post_order ~f:(fun pc ->
      let l = Hashtbl.find g.succs pc in
      Addr.Set.iter
        (fun pc' ->
          if is_forward g pc pc'
          then
            let d = try inter pc (Hashtbl.find dom pc') with Not_found -> pc in
            Hashtbl.replace dom pc' d)
        l);
  (* Check we have reached a fixed point (reducible graph) *)
  List.iter g.reverse_post_order ~f:(fun pc ->
      let l = Hashtbl.find g.succs pc in
      Addr.Set.iter
        (fun pc' ->
          if is_forward g pc pc'
          then
            let d = Hashtbl.find dom pc' in
            assert (inter pc d = d))
        l);
  reverse_tree dom

(* pc has at least two forward edges moving into it *)
let is_merge_node g pc = is_merge_node' g.block_order g.preds pc

let is_loop_header g pc =
  let s = try Hashtbl.find g.preds pc with Not_found -> Addr.Set.empty in
  let o = Hashtbl.find g.block_order pc in
  Addr.Set.exists (fun pc' -> Hashtbl.find g.block_order pc' >= o) s

let sort_in_post_order t l =
  List.sort ~cmp:(fun a b -> compare (block_order t a) (block_order t b)) l

(*

(* pc dominates pc' *)
let rec dominates g idom pc pc' =
  pc = pc' || (is_forward g pc pc' && dominates g idom pc (Hashtbl.find idom pc'))

let dominance_frontier g idom =
  let frontiers = Hashtbl.create 16 in
  Hashtbl.iter
    (fun pc preds ->
      if Addr.Set.cardinal preds > 1
      then
        let dom = Hashtbl.find idom pc in
        let rec loop runner =
          if runner <> dom
          then (
            add_edge frontiers runner pc;
            loop (Hashtbl.find idom runner))
        in
        Addr.Set.iter loop preds)
    g.preds;
  frontiers
*)
