(* Js_of_ocaml tests
 * http://www.ocsigen.org/js_of_ocaml/
 * Copyright (C) 2020 Hugo Heuzard
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

(* https://github.com/ocsigen/js_of_ocaml/issues/1007 *)

(* There was a bad interaction between the code generating trampoline
   for recursive functions and the code responsible for capturing
   mutable variable in closures.

   In practice, the issue would trigger when mutually recursives
   functions, where recursion is not in tail position, appear inside a
   for-loop.

   In the test below, [f] compiles into a for loop and
   [MyList.stable_sort] gets inlined. *)

let%expect_test _ =
  let prog =
    {|
module M : sig
  type t
  val myfun : t -> unit
  val x : t
end = struct
  module MyList : sig
    val stable_sort : ('a -> 'a -> int) -> 'a list -> 'a list
  end = struct
    let rec length_aux len = function
      | [] -> len
      | _ :: l -> length_aux (len + 1) l

    let length l = length_aux 0 l

    let rec rev_append l1 l2 =
      match l1 with
      | [] -> l2
      | a :: l -> rev_append l (a :: l2)

    let stable_sort cmp l =
      let rec rev_merge l1 l2 accu =
        match l1, l2 with
        | [], l2 -> rev_append l2 accu
        | l1, [] -> rev_append l1 accu
        | h1 :: t1, h2 :: t2 ->
          if cmp h1 h2 <= 0
          then rev_merge t1 l2 (h1 :: accu)
          else rev_merge l1 t2 (h2 :: accu)
      in
      let rec rev_merge_rev l1 l2 accu =
        match l1, l2 with
        | [], l2 -> rev_append l2 accu
        | l1, [] -> rev_append l1 accu
        | h1 :: t1, h2 :: t2 ->
          if cmp h1 h2 > 0
          then rev_merge_rev t1 l2 (h1 :: accu)
          else rev_merge_rev l1 t2 (h2 :: accu)
      in
      let rec sort n l =
        match n, l with
        | 2, x1 :: x2 :: tl ->
          let s = if cmp x1 x2 <= 0 then [ x1; x2 ] else [ x2; x1 ] in
          s, tl
        | 3, x1 :: x2 :: x3 :: tl ->
          let s =
            if cmp x1 x2 <= 0
            then
              if cmp x2 x3 <= 0
              then [ x1; x2; x3 ]
              else if cmp x1 x3 <= 0
              then [ x1; x3; x2 ]
              else [ x3; x1; x2 ]
            else if cmp x1 x3 <= 0
            then [ x2; x1; x3 ]
            else if cmp x2 x3 <= 0
            then [ x2; x3; x1 ]
            else [ x3; x2; x1 ]
          in
          s, tl
        | n, l ->
          let n1 = n asr 1 in
          let n2 = n - n1 in
          let s1, l2 = rev_sort n1 l in
          let s2, tl = rev_sort n2 l2 in
          rev_merge_rev s1 s2 [], tl
      and rev_sort n l =
        match n, l with
        | 2, x1 :: x2 :: tl ->
          let s = if cmp x1 x2 > 0 then [ x1; x2 ] else [ x2; x1 ] in
          s, tl
        | 3, x1 :: x2 :: x3 :: tl ->
          let s =
            if cmp x1 x2 > 0
            then
              if cmp x2 x3 > 0
              then [ x1; x2; x3 ]
              else if cmp x1 x3 > 0
              then [ x1; x3; x2 ]
              else [ x3; x1; x2 ]
            else if cmp x1 x3 > 0
            then [ x2; x1; x3 ]
            else if cmp x2 x3 > 0
            then [ x2; x3; x1 ]
            else [ x3; x2; x1 ]
          in
          s, tl
        | n, l ->
          let n1 = n asr 1 in
          let n2 = n - n1 in
          let s1, l2 = sort n1 l in
          let s2, tl = sort n2 l2 in
          rev_merge s1 s2 [], tl
      in
      let len = length l in
      if len < 2 then l else fst (sort len l)
  end

  type t =
    | Empty
    | Node of t

  let rec myfun x =
    match x with
    | Empty -> ()
    | Node next ->
      let _ = MyList.stable_sort compare [ 1; 2; 3; 4 ] in
      myfun next

  let x = Node Empty

end

let ()  = M.myfun M.x
|}
  in
  Util.compile_and_run prog;
  [%expect {| |}];
  let program = Util.compile_and_parse prog in
  Util.print_fun_decl program (Some "myfun");
  [%expect
    {|
    function myfun(x){
     var x$0 = x;
     for(;;){
      if(! x$0) return 0;
      var
       next = x$0[1],
       rev_sort =
         function(n, l){
          if(2 === n){
           if(l){
            var match = l[2];
            if(match){
             var
              tl = match[2],
              x2 = match[1],
              x1 = l[1],
              s =
                0 < caml_int_compare(x1, x2)
                 ? [0, x1, [0, x2, 0]]
                 : [0, x2, [0, x1, 0]];
             return [0, s, tl];
            }
           }
          }
          else if(3 === n && l){
           var _d_ = l[2];
           if(_d_){
            var match$2 = _d_[2];
            if(match$2){
             var
              tl$1 = match$2[2],
              x3 = match$2[1],
              x2$0 = _d_[1],
              x1$0 = l[1],
              s$0 =
                0 < caml_int_compare(x1$0, x2$0)
                 ? 0
                   < caml_int_compare(x2$0, x3)
                   ? [0, x1$0, [0, x2$0, [0, x3, 0]]]
                   : 0
                     < caml_int_compare(x1$0, x3)
                     ? [0, x1$0, [0, x3, [0, x2$0, 0]]]
                     : [0, x3, [0, x1$0, [0, x2$0, 0]]]
                 : 0
                   < caml_int_compare(x1$0, x3)
                   ? [0, x2$0, [0, x1$0, [0, x3, 0]]]
                   : 0
                     < caml_int_compare(x2$0, x3)
                     ? [0, x2$0, [0, x3, [0, x1$0, 0]]]
                     : [0, x3, [0, x2$0, [0, x1$0, 0]]];
             return [0, s$0, tl$1];
            }
           }
          }
          var
           n1 = n >> 1,
           n2 = n - n1 | 0,
           match$0 = sort(n1, l),
           l2$0 = match$0[2],
           s1 = match$0[1],
           match$1 = sort(n2, l2$0),
           tl$0 = match$1[2],
           s2 = match$1[1],
           l1 = s1,
           l2 = s2,
           accu = 0;
          for(;;){
           if(l1){
            if(l2){
             var t2 = l2[2], h2 = l2[1], t1 = l1[2], h1 = l1[1];
             if(0 < caml_int_compare(h1, h2)){
              var accu$0 = [0, h2, accu], l2 = t2, accu = accu$0;
              continue;
             }
             var accu$1 = [0, h1, accu], l1 = t1, accu = accu$1;
             continue;
            }
            var _c_ = rev_append(l1, accu);
           }
           else
            var _c_ = rev_append(l2, accu);
           return [0, _c_, tl$0];
          }
         },
       sort =
         function(n, l){
          if(2 === n){
           if(l){
            var match = l[2];
            if(match){
             var
              tl = match[2],
              x2 = match[1],
              x1 = l[1],
              s =
                0 < caml_int_compare(x1, x2)
                 ? [0, x2, [0, x1, 0]]
                 : [0, x1, [0, x2, 0]];
             return [0, s, tl];
            }
           }
          }
          else if(3 === n && l){
           var _b_ = l[2];
           if(_b_){
            var match$2 = _b_[2];
            if(match$2){
             var
              tl$1 = match$2[2],
              x3 = match$2[1],
              x2$0 = _b_[1],
              x1$0 = l[1],
              s$0 =
                0 < caml_int_compare(x1$0, x2$0)
                 ? 0
                   < caml_int_compare(x1$0, x3)
                   ? 0
                     < caml_int_compare(x2$0, x3)
                     ? [0, x3, [0, x2$0, [0, x1$0, 0]]]
                     : [0, x2$0, [0, x3, [0, x1$0, 0]]]
                   : [0, x2$0, [0, x1$0, [0, x3, 0]]]
                 : 0
                   < caml_int_compare(x2$0, x3)
                   ? 0
                     < caml_int_compare(x1$0, x3)
                     ? [0, x3, [0, x1$0, [0, x2$0, 0]]]
                     : [0, x1$0, [0, x3, [0, x2$0, 0]]]
                   : [0, x1$0, [0, x2$0, [0, x3, 0]]];
             return [0, s$0, tl$1];
            }
           }
          }
          var
           n1 = n >> 1,
           n2 = n - n1 | 0,
           match$0 = rev_sort(n1, l),
           l2$0 = match$0[2],
           s1 = match$0[1],
           match$1 = rev_sort(n2, l2$0),
           tl$0 = match$1[2],
           s2 = match$1[1],
           l1 = s1,
           l2 = s2,
           accu = 0;
          for(;;){
           if(l1){
            if(l2){
             var t2 = l2[2], h2 = l2[1], t1 = l1[2], h1 = l1[1];
             if(0 < caml_int_compare(h1, h2)){
              var accu$0 = [0, h1, accu], l1 = t1, accu = accu$0;
              continue;
             }
             var accu$1 = [0, h2, accu], l2 = t2, accu = accu$1;
             continue;
            }
            var _a_ = rev_append(l1, accu);
           }
           else
            var _a_ = rev_append(l2, accu);
           return [0, _a_, tl$0];
          }
         },
       len = 0,
       param = l;
      for(;;){
       if(! param){if(2 <= len) sort(len, l); var x$0 = next; break;}
       var l$0 = param[2], len$0 = len + 1 | 0, len = len$0, param = l$0;
      }
     }
    }
    //end |}]

let%expect_test _ =
  let prog =
    {|
module M : sig
  val run : unit -> unit
end = struct
  let even i =
    let rec odd = function
     | 0 -> false
     | 1 -> not (not (even 0))
     | 2 -> not (not (even 1))
     | n -> not (not (even (n - 1)))
    and even = function
     | 0 -> true
     | 1 -> not (not (odd 0))
     | 2 -> not (not (odd 1))
     | n -> not (not (odd (n - 1)))
    in even i

 let run () =
   for i = 0 to 4 do
     ignore (even (i) : bool)
   done
end

let ()  = M.run ()
|}
  in
  Util.compile_and_run prog;
  [%expect {| |}];
  let program = Util.compile_and_parse prog in
  Util.print_fun_decl program (Some "run");
  [%expect
    {|
    function run(param){
     var i = 0;
     for(;;){
      var
       even =
         function(n){
          if(2 < n >>> 0) return 1 - (1 - odd(n - 1 | 0));
          switch(n){
            case 0:
             return 1;
            case 1:
             return 1 - (1 - odd(0));
            default: return 1 - (1 - odd(1));
          }
         },
       odd =
         function(n){
          if(2 < n >>> 0) return 1 - (1 - even(n - 1 | 0));
          switch(n){
            case 0:
             return 0;
            case 1:
             return 1 - (1 - even(0));
            default: return 1 - (1 - even(1));
          }
         };
      even(i);
      var _a_ = i + 1 | 0;
      if(4 === i) return 0;
      var i = _a_;
     }
    }
    //end |}]

let%expect_test _ =
  let prog =
    {|

let list_rev = List.rev
let list_iter = List.iter
(* Avoid to expose the offset of stdlib modules *)
let () = ignore (list_rev [])
let () = ignore (list_iter (fun f -> f ()) [])

module M : sig
  val run : unit -> unit
end = struct
  let delayed = ref []
  let even i =
    let rec odd = function
     | 0 ->
       let f () = Printf.printf "in odd, called with %d\n" i in
       delayed := f :: !delayed;
       f ();
       false
     | 1 -> not (not (even 0))
     | 2 -> not (not (even 1))
     | n -> not (not (even (n - 1)))
    and even = function
     | 0 ->
       let f () = Printf.printf "in even, called with %d\n" i in
       delayed := f :: !delayed;
       f ();
       true
     | 1 -> not (not (odd 0))
     | 2 -> not (not (odd 1))
     | n -> not (not (odd (n - 1)))
    in even i

 let run () =
   for i = 0 to 4 do
     ignore (even (i) : bool)
   done;
   list_iter (fun f -> f ()) (list_rev !delayed)
end

let ()  = M.run ()
|}
  in
  Util.compile_and_run prog;
  [%expect
    {|
    in even, called with 0
    in odd, called with 1
    in even, called with 2
    in odd, called with 3
    in even, called with 4
    in even, called with 0
    in odd, called with 1
    in even, called with 2
    in odd, called with 3
    in even, called with 4 |}];
  let program = Util.compile_and_parse prog in
  Util.print_fun_decl program (Some "run");
  [%expect
    {|
    function run(param){
     var i = 0;
     for(;;){
      var
       closures =
         function(i){
          function even(n){
           if(2 < n >>> 0) return 1 - (1 - odd(n - 1 | 0));
           switch(n){
             case 0:
              var
               f = function(param){return caml_call2(Stdlib_Printf[2], _c_, i);};
              delayed[1] = [0, f, delayed[1]];
              f(0);
              return 1;
             case 1:
              return 1 - (1 - odd(0));
             default: return 1 - (1 - odd(1));
           }
          }
          function odd(n){
           if(2 < n >>> 0) return 1 - (1 - even(n - 1 | 0));
           switch(n){
             case 0:
              var
               f = function(param){return caml_call2(Stdlib_Printf[2], _b_, i);};
              delayed[1] = [0, f, delayed[1]];
              f(0);
              return 0;
             case 1:
              return 1 - (1 - even(0));
             default: return 1 - (1 - even(1));
           }
          }
          var block = [0, even, odd];
          return block;
         },
       closures$0 = closures(i),
       even = closures$0[1];
      even(i);
      var _e_ = i + 1 | 0;
      if(4 === i){
       var _d_ = caml_call1(list_rev, delayed[1]);
       return caml_call2(list_iter, function(f){return caml_call1(f, 0);}, _d_);
      }
      var i = _e_;
     }
    }
    //end |}]

let%expect_test _ =
  let prog =
    {|

let list_rev = List.rev
let list_iter = List.iter
(* Avoid to expose the offset of stdlib modules *)
let () = ignore (list_rev [])
let () = ignore (list_iter (fun f -> f ()) [])

module M : sig
  val run : unit -> unit
end = struct
  let delayed = ref []
  let even i =
    let rec odd = function
     | 0 -> `Cont (fun () ->
       let f () = Printf.printf "in odd, called with %d\n" i in
       delayed := f :: !delayed;
       f ();
       `Done false)
     | 1 -> `Cont (fun () -> even 0)
     | 2 -> `Cont (fun () -> even 1)
     | n -> `Cont (fun () -> even (n - 1))
    and even = function
     | 0 -> `Cont (fun () ->
       let f () = Printf.printf "in even, called with %d\n" i in
       delayed := f :: !delayed;
       f ();
       `Done true)
     | 1 -> `Cont (fun () -> odd 0)
     | 2 -> `Cont (fun () -> odd 1)
     | n -> `Cont (fun () -> odd (n - 1))
    in even i

 let run () =
   for i = 0 to 4 do
      let rec r = function
        | `Done x -> x
        | `Cont f -> r (f ())
      in
      ignore (r  (even (i)) : bool)
   done;
   list_iter (fun f -> f ()) (list_rev !delayed)
end

let ()  = M.run ()
|}
  in
  Util.compile_and_run prog;
  [%expect
    {|
    in even, called with 0
    in odd, called with 1
    in even, called with 2
    in odd, called with 3
    in even, called with 4
    in even, called with 0
    in odd, called with 1
    in even, called with 2
    in odd, called with 3
    in even, called with 4 |}];
  let program = Util.compile_and_parse prog in
  Util.print_fun_decl program (Some "run");
  [%expect
    {|
    function run(param){
     var i = 0;
     for(;;){
      var
       closures =
         function(i){
          function even(n){
           if(2 < n >>> 0)
            return [0, 748545554, function(param){return odd(n - 1 | 0);}];
           switch(n){
             case 0:
              return [0,
                      748545554,
                      function(param){
                       function f(param){
                        return caml_call2(Stdlib_Printf[2], _d_, i);
                       }
                       delayed[1] = [0, f, delayed[1]];
                       f(0);
                       return _e_;
                      }];
             case 1:
              return [0, 748545554, function(param){return odd(0);}];
             default: return [0, 748545554, function(param){return odd(1);}];
           }
          }
          function odd(n){
           if(2 < n >>> 0)
            return [0, 748545554, function(param){return even(n - 1 | 0);}];
           switch(n){
             case 0:
              return [0,
                      748545554,
                      function(param){
                       function f(param){
                        return caml_call2(Stdlib_Printf[2], _b_, i);
                       }
                       delayed[1] = [0, f, delayed[1]];
                       f(0);
                       return _c_;
                      }];
             case 1:
              return [0, 748545554, function(param){return even(0);}];
             default: return [0, 748545554, function(param){return even(1);}];
           }
          }
          var block = [0, even, odd];
          return block;
         },
       closures$0 = closures(i),
       even = closures$0[1],
       param$0 = even(i);
      for(;;){
       if(759635106 <= param$0[1]){
        var _g_ = i + 1 | 0;
        if(4 !== i){var i = _g_; break;}
        var _f_ = caml_call1(list_rev, delayed[1]);
        return caml_call2(list_iter, function(f){return caml_call1(f, 0);}, _f_);
       }
       var f = param$0[2], param$0 = f(0);
      }
     }
    }
    //end |}]
