
(*FIX: this should probably be somewhere else... *)
module VarPrinter = struct
  let reserved = Hashtbl.create 107

  let add_reserved s =
    if String.length s <= 5 then Hashtbl.replace reserved s ()

  let _ =
    List.iter add_reserved
      ["break"; "case"; "catch"; "do"; "else"; "for"; "if"; "in"; "new";
       "this"; "throw"; "try"; "var"; "void"; "while"; "with"; "class";
       "enum"; "super"; "const"; "yield"; "let"]

  let known = Hashtbl.create 1001

  let last = ref (-1)

  let c1 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_$"
  let c2 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$"

  let rec format_var x =
    let char c x = String.make 1 (c.[x]) in
    if x < 54 then
       char c1 x
    else
      format_var ((x - 54) / 64) ^ char c2 ((x - 54) mod 64)

  let rec to_string i =
    try
      Hashtbl.find known i
    with Not_found ->
      incr last;
      let j = !last in
      let s = format_var j in
      if Hashtbl.mem reserved s then
        to_string i
      else begin
        Hashtbl.add known i s;
        s
      end
end

let add_reserved_name = VarPrinter.add_reserved

module Var : sig
  type t
  val print : Format.formatter -> t -> unit
  val idx : t -> int
  val to_string : t -> string

  type stream
  val make_stream : unit -> stream
  val next : stream -> t * stream

  val fresh : unit -> t

  val count : unit -> int

  val compare : t -> t -> int
end = struct

  type t = int * int

  let last_var = ref 0

  type stream = int

  let c = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$"

  let rec format_var x =
    let char x = String.make 1 (c.[x]) in
    if x < 65 then
       char (x - 1)
    else
      format_var (x / 64) ^ char (x mod 64)

(*
  let to_string (x, i) = "o$" ^ format_var i(*format_var x ^ Format.sprintf "%d" i*)
*)
  let to_string (x, i) = VarPrinter.to_string i

  let print f x = Format.fprintf f "%s" (to_string x)

  let make_stream () = 1

  let next current =
    incr last_var;
    ((current, !last_var), current + 1)

  let fresh () = incr last_var; (0, !last_var)

  let count () = !last_var + 1

  let idx v = snd v

  let compare v1 v2 = compare (idx v1) (idx v2)
end

module VarSet = Set.Make (Var)
module VarMap = Map.Make (Var)

type addr = int

module AddrSet = Util.IntSet
module AddrMap = Util.IntMap

type cont = addr * Var.t list

type prim =
    Vectlength
  | Array_get
  | Extern of string
  | Not | Neg | IsInt
  | Eq | Neq | Lt | Le | Ult
  | WrapInt

type constant =
    String of string
  | Float of float
  | Float_array of float array
  | Int32 of int32
  | Nativeint of nativeint
  | Int64 of int64
  | Tuple of int * constant array
  | Int of int

type prim_arg =
    Pv of Var.t
  | Pc of constant

type expr =
    Const of int
  | Apply of Var.t * Var.t list * int option
  | Block of int * Var.t array
  | Field of Var.t * int
  | Closure of Var.t list * cont
  | Constant of constant
  | Prim of prim * prim_arg list
  | Variable of Var.t

type instr =
    Let of Var.t * expr
  | Set_field of Var.t * int * Var.t
  | Offset_ref of Var.t * int
  | Array_set of Var.t * Var.t * Var.t

type cond = IsTrue | CEq of int | CLt of int | CLe of int | CUlt of int

type last =
    Return of Var.t
  | Raise of Var.t
  | Stop
  | Branch of cont
  | Cond of cond * Var.t * cont * cont
  | Switch of Var.t * cont array * cont array
  | Pushtrap of cont * Var.t * cont * addr
  | Poptrap of cont

type block =
  { params : Var.t list;
    handler : (Var.t * cont) option;
    body : instr list;
    branch : last }

type program = addr * block AddrMap.t * addr

(****)

let dummy_cont = (-1, [])

let is_dummy_cont (pc, _) = pc < 0

(****)

let rec print_list pr f l =
  match l with
    []     -> ()
  | [x]    -> pr f x
  | x :: r -> Format.fprintf f "%a, %a" pr x (print_list pr) r

let print_var_list = print_list Var.print

let print_cont f ((pc, args) as cont) =
  if is_dummy_cont cont then Format.fprintf f "<dummy>" else
  Format.fprintf f "%d (%a)" pc print_var_list args

let rec print_constant f x =
  match x with
    String s ->
      Format.fprintf f "%S" s
  | Float fl ->
      Format.fprintf f "%.12g" fl
  | Float_array a ->
      Format.fprintf f "[|";
      for i = 0 to Array.length a - 1 do
        if i > 0 then Format.fprintf f ", ";
        Format.fprintf f "%.12g" a.(i)
      done;
      Format.fprintf f "|]"
  | Int32 i ->
      Format.fprintf f "%ldl" i
  | Nativeint i ->
      Format.fprintf f "%ndn" i
  | Int64 i ->
      Format.fprintf f "%LdL" i
  | Tuple (tag, a) ->
      Format.fprintf f "<%d>" tag;
      begin match Array.length a with
        0 -> ()
      | 1 ->
          Format.fprintf f "("; print_constant f a.(0); Format.fprintf f ")"
      | n ->
          Format.fprintf f "("; print_constant f a.(0);
          for i = 1 to n - 1 do
            Format.fprintf f ", "; print_constant f a.(i)
          done;
          Format.fprintf f ")"
      end
   | Int i ->
       Format.fprintf f "%d" i

let print_arg f a =
  match a with
    Pv x -> Var.print f x
  | Pc c -> print_constant f c

let binop s =
  match s with
    "%int_add" -> "+"
  | "%int_sub" -> "-"
  | "%int_mul" -> "*"
  | "%int_div" -> "/"
  | "%int_mod" -> "%"
  | "%int_and" -> "&"
  | "%int_or"  -> "|"
  | "%int_xor" -> "^"
  | "%int_lsl" -> "<<"
  | "%int_lsr" -> ">>>"
  | "%int_asr" -> ">>"
  | _              -> raise Not_found


let print_prim f p l =
  match p, l with
    Vectlength, [x]   -> Format.fprintf f "%a.length" print_arg x
  | Array_get, [x; y] -> Format.fprintf f "%a[%a]" print_arg x print_arg y
  | Extern s, [x; y]  ->
      begin try
        Format.fprintf f "%a %s %a" print_arg x (binop s) print_arg y
      with Not_found ->
        Format.fprintf f "\"%s\"(%a)" s (print_list print_arg) l
      end
  | Extern s, _       -> Format.fprintf f "\"%s\"(%a)"
                           s (print_list print_arg) l
  | Not, [x]          -> Format.fprintf f "!%a" print_arg x
  | Neg, [x]          -> Format.fprintf f "-%a" print_arg x
  | IsInt, [x]        -> Format.fprintf f "is_int(%a)" print_arg x
  | Eq,  [x; y]       -> Format.fprintf f "%a === %a" print_arg x print_arg y
  | Neq, [x; y]       -> Format.fprintf f "!(%a === %a)" print_arg x print_arg y
  | Lt,  [x; y]       -> Format.fprintf f "%a < %a" print_arg x print_arg y
  | Le,  [x; y]       -> Format.fprintf f "%a <= %a" print_arg x print_arg y
  | Ult, [x; y]       -> Format.fprintf f "%a <= %a" print_arg x print_arg y
  | WrapInt, [x]      -> Format.fprintf f "to_int(%a)" print_arg x
  | _                 -> assert false

let print_expr f e =
  match e with
    Const i ->
      Format.fprintf f "%d" i
  | Apply (g, l, n) ->
      if n = Some (List.length l) then
        Format.fprintf f "%a!(%a)" Var.print g print_var_list l
      else
        Format.fprintf f "%a(%a)" Var.print g print_var_list l
  | Block (t, a) ->
      Format.fprintf f "{tag=%d" t;
      for i = 0 to Array.length a - 1 do
        Format.fprintf f "; %d = %a" i Var.print a.(i)
      done;
      Format.fprintf f "}"
  | Field (x, i) ->
      Format.fprintf f "%a[%d]" Var.print x i
  | Closure (l, cont) ->
      Format.fprintf f "fun(%a){%a}" print_var_list l print_cont cont
  | Constant c ->
      Format.fprintf f "CONST{%a}" print_constant c
  | Prim (p, l) ->
      print_prim f p l
  | Variable x ->
      Format.fprintf f "%a" Var.print x

let print_instr f i =
  match i with
    Let (x, e)    ->
      Format.fprintf f "%a = %a" Var.print x print_expr e
  | Set_field (x, i, y) ->
      Format.fprintf f "%a[%d] = %a" Var.print x i Var.print y
  | Offset_ref (x, i) ->
      Format.fprintf f "%a[0] += %d" Var.print x i
  | Array_set (x, y, z) ->
      Format.fprintf f "%a[%a] = %a" Var.print x Var.print y Var.print z

let print_cond f (c, x) =
  match c with
    IsTrue -> Var.print f x
  | CEq n  -> Format.fprintf f "%d = %a" n Var.print x
  | CLt n  -> Format.fprintf f "%d < %a" n Var.print x
  | CLe n  -> Format.fprintf f "%d <= %a" n Var.print x
  | CUlt n -> Format.fprintf f "%d < %a" n Var.print x

let print_last f l =
  match l with
    Return x ->
      Format.fprintf f "return %a" Var.print x
  | Raise x ->
      Format.fprintf f "raise %a" Var.print x
  | Stop ->
      Format.fprintf f "stop"
  | Branch cont ->
      Format.fprintf f "branch %a" print_cont cont
  | Cond (cond, x, cont1, cont2) ->
      Format.fprintf f "if %a then %a else %a" print_cond (cond, x)
        print_cont cont1 print_cont cont2
  | Switch (x, a1, a2) ->
      Format.fprintf f "switch %a {" Var.print x;
      Array.iteri
        (fun i cont -> Format.fprintf f "int %d -> %a; " i print_cont cont) a1;
      Array.iteri
        (fun i cont -> Format.fprintf f "tag %d -> %a; " i print_cont cont) a2;
      Format.fprintf f "}"
  | Pushtrap (cont1, x, cont2, pc) ->
      Format.fprintf f "pushtrap %a handler %a => %a continuation %d"
        print_cont cont1 Var.print x print_cont cont2 pc
  | Poptrap cont ->
      Format.fprintf f "poptrap %a" print_cont cont

type xinstr = Instr of instr | Last of last

let print_block annot pc block =
  Format.eprintf "==== %d (%a) ====@." pc print_var_list block.params;
  begin match block.handler with
    Some (x, cont) ->
      Format.eprintf "    handler %a => %a@." Var.print x print_cont cont
  | None ->
      ()
  end;
  List.iter
    (fun i -> Format.eprintf " %s %a@." (annot pc (Instr i)) print_instr i)
    block.body;
  Format.eprintf " %s %a@." (annot pc (Last block.branch))
    print_last block.branch;
  Format.eprintf "@."

let print_program annot (pc, blocks, _) =
  Format.eprintf "Entry point: %d@.@." pc;
  AddrMap.iter (print_block annot) blocks

(****)

let fold_closures (pc, blocks, _) f accu =
  AddrMap.fold
    (fun _ block accu ->
       List.fold_left
         (fun accu i ->
            match i with
              Let (x, Closure (params, cont)) ->
                f (Some x) params cont accu
            | _ ->
                accu)
         accu block.body)
    blocks (f None [] (pc, []) accu)

(****)

let (>>) x f = f x

let fold_children blocks pc f accu =
  let block = AddrMap.find pc blocks in
  let accu =
    match block.handler with
      Some (_, (pc, _)) -> f pc accu
    | None              -> accu
  in
  match block.branch with
    Return _ | Raise _ | Stop ->
      accu
  | Branch (pc', _) | Poptrap (pc', _) | Pushtrap ((pc', _), _, _, _) ->
      f pc' accu
  | Cond (_, _, (pc1, _), (pc2, _)) ->
      f pc1 accu >> f pc1 >> f pc2
  | Switch (_, a1, a2) ->
      accu >> Array.fold_right (fun (pc, _) accu -> f pc accu) a1
           >> Array.fold_right (fun (pc, _) accu -> f pc accu) a2
