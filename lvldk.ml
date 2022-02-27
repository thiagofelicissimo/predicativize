module T = Kernel.Term
module B = Kernel.Basic
module Env = Api.Env
module U = Unif
module L = Lvl                    

let pts_m = T.mk_Const (B.dloc) (B.mk_name (B.mk_mident "pts") (B.mk_ident "M"))
let pts_0_n = T.mk_Const (B.dloc) (B.mk_name (B.mk_mident "pts") (B.mk_ident "0_N"))
let pts_s = T.mk_Const (B.dloc) (B.mk_name (B.mk_mident "pts") (B.mk_ident "S"))
let pts_s_n = T.mk_Const (B.dloc) (B.mk_name (B.mk_mident "pts") (B.mk_ident "S_N"))          
let pts_union = T.mk_Const (B.dloc) (B.mk_name (B.mk_mident "pts") (B.mk_ident "Union"))
let pts_empty = T.mk_Const (B.dloc) (B.mk_name (B.mk_mident "pts") (B.mk_ident "Empty"))

let sort_ty = T.mk_Const (B.dloc) (B.mk_name (B.mk_mident "pts") (B.mk_ident "Lvl"))

let metavar_te = T.mk_Const B.dloc (B.mk_name (B.mk_mident "") (B.mk_ident "var"))
              
let ( let* ) o f =
  match o with
  | None -> None
  | Some x -> f x

exception Nested_apps       
            
let rec extract_int t =
  let open T in
  match t with
  | App(Const(_, n1), t1, []) when (B.string_of_ident (B.id n1) = "S_N") ->
     let* m = extract_int t1 in
     Some (1 + m)
  | Const(_, n) when (B.string_of_ident (B.id n) = "0_N") -> Some 0
  | App(App(_,_,_),_,_) -> raise Nested_apps                                                           
  | _ -> None

let rec extract_lvl_set t =
  let open T in
  match t with
  | Const(_, n) when (B.string_of_ident (B.id n) = "Empty") -> Some []
  | App(Const(_, n1), t1, [Const(_,n2)]) when
         (B.string_of_ident (B.id n1) = "S" && String.get (B.string_of_ident (B.id n2)) 0 = '?') ->
     let* m = extract_int t1 in
     let var = B.string_of_ident (B.id n2) in
     Some [L.S(m, var)]
  | App(Const(_, n), t1, [t2]) when (B.string_of_ident (B.id n) = "Union") ->
     let* m1 = extract_lvl_set t1 in
     let* m2 = extract_lvl_set t2 in
     Some (m1 @ m2)
  | App(App(_,_,_),_,_) -> raise Nested_apps
  | _ -> None
     
let extract_lvl t =
  let open T in
  match t with
  | App(Const(_, n1), t1, [t2]) when (B.string_of_ident (B.id n1) = "M") ->
     let* m = extract_int t1 in
     let* s = extract_lvl_set t2 in
     Some (L.M(m, s))
  | App(App(_,_,_),_,_) -> raise Nested_apps     
  | _ -> None

let rec int_to_term n =
  match n with
  | 0 -> pts_0_n
  | _ -> T.mk_App pts_s_n (int_to_term (n - 1)) []

       
let alvl_to_term (L.S(n,var)) =
  T.mk_App
    pts_s
    (int_to_term n)
    [T.mk_Const (B.dloc) (B.mk_name (B.mk_mident "metavar") (B.mk_ident var))]
       
let lvl_to_term (L.M(n,l)) =
  let rec alvl_list_to_term = function
    | [] -> pts_empty
    | [x] -> alvl_to_term x
    | x :: l -> T.mk_App pts_union (alvl_to_term x) [alvl_list_to_term l] in
  T.mk_App pts_m (int_to_term n) [alvl_list_to_term l]
          
let apply_subst_to_term subst te =
  let fv = ref [] in
  let rec aux te = 
    match te with
    | T.App (Const (_,name_m),Const(_,zero),[App(Const(_,name_s),Const (_,zero'),[Const(_,var_name)])])
         when (B.string_of_ident (B.id zero) = "0_N" && B.string_of_ident (B.id zero') = "0_N"
               && B.string_of_ident (B.id name_m) = "M" && B.string_of_ident (B.id name_s) = "S") ->
       begin match subst @@ B.string_of_ident @@ B.id var_name with
       | Some t -> fv := (L.get_fv t) @ !fv; lvl_to_term t
       | None -> fv := (B.string_of_ident @@ B.id var_name) :: !fv; te end

    | T.App (f, a1, al) -> T.mk_App (aux f) (aux a1) (List.map aux al)
    | T.Lam (l, id, t, body) -> T.mk_Lam l id (Option.map aux t) (aux body)
    | T.Pi (l, id, a, b) -> T.mk_Pi l id (aux a) (aux b)
    | _ -> te in
  let te = aux te in
  let remove_duplicates = List.fold_left (fun acc x -> if List.mem x acc then acc else x :: acc) [] in
  (te, remove_duplicates !fv)


(*    
let rec apply_subst_to_term subst te =
  match te with
  | App (Const (_, name_m), Const (_, zero), App (Const (_, name_s), Const (_, zero'), var_name))
       when (B.string_of_ident @@ B.id zero = "0_N" && B.string_of_ident @@ B.id zero' = "0_N"
             && B.string_of_ident @@ B.id name_m = "M" && B.string_of_ident @@ B.id name_s = "S") ->
     begin match subst @@ B.string_of_ident @@ B.id name with
     | Some t -> [L.get_fv t], lvl_to_term t
     | None -> [var_name], te end
  | App (f,a1,al) ->
     let f_fv, f = apply_subst_to_term subst f in
     let a1_fv, a1 = apply_subst_to_term subst a1 in
     let al_fv, al = List.map (apply_subst_to_term subst) al in
     
     mk_App (insert_lvl_metas f) (insert_lvl_metas a1) (List.map insert_lvl_metas al)
  | Lam (l,id,t,body) ->
     mk_Lam l id (Option.map insert_lvl_metas t) (insert_lvl_metas body)
  | Pi (l,id,a,b) ->
     mk_Pi l id (insert_lvl_metas a) (insert_lvl_metas b)
  | Kind | Type _ | DB _ | Const _ -> t
 *)
