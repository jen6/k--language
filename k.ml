(*
 * SNU 4190.310 Programming Languages 2015 Fall
 *  K- Interpreter Skeleton Code
 * Jaeseung Choi (jschoi@ropas.snu.ac.kr)
 *)

(* Location Signature *)
open List
module type LOC =
sig
  type t
  val base : t
  val equal : t -> t -> bool
  val diff : t -> t -> int
  val increase : t -> int -> t
end

module Loc : LOC =
struct
  type t = Location of int
  let base = Location(0)
  let equal (Location(a)) (Location(b)) = (a = b)
  let diff (Location(a)) (Location(b)) = a - b
  let increase (Location(base)) n = Location(base+n)
end

(* Memory Signature *)
module type MEM = 
sig
  type 'a t
  exception Not_allocated
  exception Not_initialized
  val empty : 'a t (* get empty memory *)
  val load : 'a t -> Loc.t  -> 'a (* load value : Mem.load mem loc => value *)
  val store : 'a t -> Loc.t -> 'a -> 'a t (* save value : Mem.store mem loc value => mem' *)
  val alloc : 'a t -> Loc.t * 'a t (* get fresh memory cell : Mem.alloc mem => (loc, mem') *)
end

(* Environment Signature *)
module type ENV =
sig
  type ('a, 'b) t
  exception Not_bound
  val empty : ('a, 'b) t (* get empty environment *)
  val lookup : ('a, 'b) t -> 'a -> 'b (* lookup environment : Env.lookup env key => content *)
  val bind : ('a, 'b) t -> 'a -> 'b -> ('a, 'b) t  (* id binding : Env.bind env key content => env'*)
end

(* Memory Implementation *)
module Mem : MEM =
struct
  exception Not_allocated
  exception Not_initialized
  type 'a content = V of 'a | U
  type 'a t = M of Loc.t * 'a content list
  let empty = M (Loc.base,[])

  let rec replace_nth = fun l n c -> 
    match l with
    | h::t -> if n = 1 then c :: t else h :: (replace_nth t (n - 1) c)
    | [] -> raise Not_allocated

  let load (M (boundary,storage)) loc =
    match (List.nth storage ((Loc.diff boundary loc) - 1)) with
    | V v -> v 
    | U -> raise Not_initialized

  let store (M (boundary,storage)) loc content =
    M (boundary, replace_nth storage (Loc.diff boundary loc) (V content))

  let alloc (M (boundary,storage)) = 
    (boundary, M (Loc.increase boundary 1, U :: storage))
end

(* Environment Implementation *)
module Env : ENV=
struct
  exception Not_bound
  type ('a, 'b) t = E of ('a -> 'b)
  let empty = E (fun x -> raise Not_bound)
  let lookup (E (env)) id = env id
  let bind (E (env)) id loc = E (fun x -> if x = id then loc else env x)
end

(*
 * K- Interpreter
 *)
module type KMINUS =
sig
  exception Error of string
  type id = string
  type exp =
  | NUM of int | TRUE | FALSE | UNIT
  | VAR of id
  | ADD of exp * exp
  | SUB of exp * exp
  | MUL of exp * exp
  | DIV of exp * exp
  | EQUAL of exp * exp
  | LESS of exp * exp
  | NOT of exp
  | SEQ of exp * exp            (* sequence *)
  | IF of exp * exp * exp       (* if-then-else *)
  | WHILE of exp * exp          (* while loop *)
  | LETV of id * exp * exp      (* variable binding *)
  | LETF of id * id list * exp * exp (* procedure binding *)
  | CALLV of id * exp list      (* call by value *)
  | CALLR of id * id list       (* call by referenece *)
  | RECORD of (id * exp) list   (* record construction *)
  | FIELD of exp * id           (* access record field *)
  | ASSIGN of id * exp          (* assgin to variable *)
  | ASSIGNF of exp * id * exp   (* assign to record field *)
  | READ of id
  | WRITE of exp
    
  type program = exp
  type memory
  type env
  type value =
  | Num of int
  | Bool of bool
  | Unit
  | Record of (id -> Loc.t)
  val emptyMemory : memory
  val emptyEnv : env
  val run : memory * env * program -> value
end

module K : KMINUS =
struct
  exception Error of string

  type id = string
  type exp =
  | NUM of int | TRUE | FALSE | UNIT
  | VAR of id
  | ADD of exp * exp
  | SUB of exp * exp
  | MUL of exp * exp
  | DIV of exp * exp
  | EQUAL of exp * exp
  | LESS of exp * exp
  | NOT of exp
  | SEQ of exp * exp            (* sequence *)
  | IF of exp * exp * exp       (* if-then-else *)
  | WHILE of exp * exp          (* while loop *)
  | LETV of id * exp * exp      (* variable binding *)
  | LETF of id * id list * exp * exp (* procedure binding *)
  | CALLV of id * exp list      (* call by value *)
  | CALLR of id * id list       (* call by referenece *)
  | RECORD of (id * exp) list   (* record construction *)
  | FIELD of exp * id           (* access record field *)
  | ASSIGN of id * exp          (* assgin to variable *)
  | ASSIGNF of exp * id * exp   (* assign to record field *)
  | READ of id
  | WRITE of exp

  type program = exp

  type value =
  | Num of int
  | Bool of bool
  | Unit
  | Record of (id -> Loc.t)
    
  type memory = value Mem.t
  type env = (id, env_entry) Env.t
  and  env_entry = Addr of Loc.t | Proc of id list * exp * env

  let emptyMemory = Mem.empty
  let emptyEnv = Env.empty

  let value_int v =
    match v with
    | Num n -> n
    | _ -> raise (Error "TypeError : not int")

  let value_bool v =
    match v with
    | Bool b -> b
    | _ -> raise (Error "TypeError : not bool")

  let value_unit v =
      match v with
      | Unit -> ()
      | _ -> raise (Error "TypeError : not unit")

  let value_record v =
      match v with
      | Record r -> r
      | _ -> raise (Error "TypeError : not record")

  let lookup_env_loc e x =
    try
      (match Env.lookup e x with
      | Addr l -> l
      | Proc _ -> raise (Error "TypeError : not addr")) 
    with Env.Not_bound -> raise (Error "Unbound")

  let lookup_env_proc e f =
    try
      (match Env.lookup e f with
      | Addr _ -> raise (Error "TypeError : not proc") 
      | Proc (id_list, exp, env) -> (id_list, exp, env))
    with Env.Not_bound -> raise (Error "Unbound")

  let rec eval mem env e =
    match e with
    | VAR x ->
      let l = lookup_env_loc env x in
      let v = Mem.load mem l in
      (v, mem)
    | READ x -> 
      let v = Num (read_int()) in
      let l = lookup_env_loc env x in
      (v, Mem.store mem l v)
    | WRITE e ->
      let (v, mem') = eval mem env e in
      let n = value_int v in
      let _ = print_endline (string_of_int n) in
      (Num n, mem')
    | LETV (x, e1, e2) -> (*variable binding*)
      let (v, mem') = eval mem env e1 in
      let (l, mem'') = Mem.alloc mem' in
      eval (Mem.store mem'' l v) (Env.bind env x (Addr l)) e2
    | LETF (funid, arguList, command, e1) ->
      eval mem (Env.bind env funid (Proc (arguList, command, env))) e1
    | ASSIGN (x, e) ->  (*assign to variable*)
      let (v, mem') = eval mem env e in
      let l = lookup_env_loc env x in
      (v, Mem.store mem' l v)
    | TRUE -> Bool true, mem
    | FALSE -> Bool false, mem
    | NUM value -> Num value, mem
    | UNIT -> Unit, mem
    | ADD (e1, e2) ->
      let (v1, m') = eval mem env e1 in
      let n1 = value_int v1 in
      let (v2, m'') = eval m' env e2 in
      let n2 = value_int v2 in
      (Num(n1 + n2), m'')
    | SUB (e1, e2) ->
      let (v1, m') = eval mem env e1 in
      let n1 = value_int v1 in
      let (v2, m'') = eval m' env e2 in
      let n2 = value_int v2 in
     (Num(n1 - n2), m'')
    | MUL (e1, e2) ->
      let (v1, m') = eval mem env e1 in
      let n1 = value_int v1 in
      let (v2, m'') = eval m' env e2 in
      let n2 = value_int v2 in
      (Num(n1 * n2), m'')
    | DIV (e1, e2)->
      let (v1, m') = eval mem env e1 in
      let n1 = value_int v1 in
      let (v2, m'') = eval m' env e2 in
      let n2 = value_int v2 in
      (Num(n1 / n2), m'')
    | SEQ (e1, e2) ->
      let (v1, m') = eval mem env e1 in
      let (v2, m'') = eval m' env e2 in
     (v2, m'')
    | CALLV (funid, expList) ->
      let (arguList,command, lenv) = lookup_env_proc env funid in
      (let rec conArgu argl expl cmem cenv =
          (
          match (argl, expl) with
          | ([], []) -> 
            let cenv' = Env.bind cenv funid (Proc (arguList, command, lenv)) in 
            eval cmem cenv' command 
          | (arg :: al, exp :: el) -> 
            let (ev,m') = eval cmem env exp in
            let (l, m'') = Mem.alloc m' in
            conArgu al el (Mem.store m'' l ev) (Env.bind cenv arg (Addr l))
          ) in
      conArgu arguList expList mem lenv
      )
    |CALLR (funid, idList) ->
      let (arguList, command, lenv) = lookup_env_proc env funid in
      (let rec conArgu argl idl cenv =
          ( 
          match (argl, idl) with
          | ([], []) -> 
            let cenv' = Env.bind cenv funid (Proc (arguList, command, lenv)) in
            eval mem cenv' command
          | (arg :: al, id :: idl) ->
             let l = lookup_env_loc env id in
             conArgu al idl (Env.bind cenv arg (Addr l))
          ) in 
      conArgu arguList idList lenv
      ) 
    | IF (cond, texp, fexp) ->
      let (evcond, m') = eval mem env cond in
      if (value_bool evcond) then
          eval m' env texp
      else
          eval m' env fexp
    | NOT cond -> 
      let (b, m') = eval mem env cond in
      if (value_bool b) then
          ((Bool false), m')
      else
          ((Bool true), m')
    | LESS (e1, e2) ->
      let (n1 , m') = eval mem env e1 in
      let (n2, m'') = eval m' env e2 in
      ((Bool (n1 < n2)), m'')
    | EQUAL (e1, e2) ->
      let (v1, m') = eval mem env e1 in
      let (v2, m'') = eval m' env e2 in
      if (v1 == v2) then
          ((Bool true), m'')
      else
          ((Bool false), m'')
    | _ -> failwith "Unimplemented" (* TODO : Implement rest of the cases *)

  let run (mem, env, pgm) = 
    let (v, _ ) = eval mem env pgm in
    v
end
