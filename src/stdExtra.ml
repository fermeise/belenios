let ( |> ) x f = f x
let ( =% ) = Z.equal

module Array = struct
  include Array

  let forall2 f a b =
    let n = Array.length a in
    n = Array.length b &&
    (let rec check i =
       if i >= 0 then f a.(i) b.(i) && check (pred i)
       else true
     in check (pred n))

  let foralli f x =
    let rec loop i =
      if i >= 0 then f i x.(i) && loop (pred i)
      else true
    in loop (pred (Array.length x))
end

module List = struct
  include List

  let iteri f xs =
    let rec loop i = function
      | [] -> []
      | x :: xs -> f i x :: loop (succ i) xs
    in List.flatten (loop 0 xs)
end

let hashB x = Cryptokit.(x |>
  hash_string (Hash.sha256 ()) |>
  transform_string (Base64.encode_compact ())
)

let load_from_file read fname =
  let i = open_in fname in
  let buf = Lexing.from_channel i in
  let lex = Yojson.init_lexer ~fname () in
  let result = read lex buf in
  close_in i;
  result

let non_empty_lines_of_file fname =
  Lwt_io.lines_of_file fname |>
  Lwt_stream.filter (fun s -> s <> "") |>
  Lwt_stream.to_list