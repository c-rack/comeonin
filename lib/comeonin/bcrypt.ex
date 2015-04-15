defmodule Comeonin.Bcrypt do
  @moduledoc """
  Module to handle bcrypt authentication.

  Bcrypt is a key derivation function for passwords designed by Niels Provos
  and David Mazières. Bcrypt uses a salt to protect against offline attacks.
  It is also an adaptive function, which means that it can be configured
  to remain slow and resistant to brute-force attacks even as computational
  power increases.

  This bcrypt implementation is based on the latest OpenBSD version, which
  fixed a small issue that affected some passwords longer than 72 characters.
  """

  use Bitwise
  alias Comeonin.Tools
  alias Comeonin.Config

  @on_load {:init, 0}

  def init do
    path = :filename.join(:code.priv_dir(:comeonin), 'bcrypt_nif')
    :ok = :erlang.load_nif(path, 0)
  end

  @doc """
  """
  def bf_init(key, key_len, salt)
  def bf_init(_, _, _), do: exit(:nif_library_not_loaded)

  @doc """
  """
  def bf_expand(state, key, key_len, salt)
  def bf_expand(_, _, _, _), do: exit(:nif_library_not_loaded)

  @doc """
  """
  def bf_encrypt(state)
  def bf_encrypt(_), do: exit(:nif_library_not_loaded)

  @doc """
  Generate a salt for use with the `hashpass` function.

  The log_rounds parameter determines the computational complexity
  of the generation of the password hash. Its default is 12, the minimum is 4,
  and the maximum is 31.
  """
  def gen_salt(log_rounds) when log_rounds in 4..31 do
    :crypto.rand_bytes(16) |> fmt_salt(log_rounds)
  end
  def gen_salt(_), do: gen_salt(Config.bcrypt_log_rounds)
  def gen_salt, do: gen_salt(Config.bcrypt_log_rounds)

  @doc """
  Hash the password using bcrypt.
  """
  def hashpass(password, salt) when is_binary(salt) and is_binary(password) do
    if byte_size(salt) == 29 do
      hashpw(password, salt)
    else
      raise ArgumentError, message: "The salt is the wrong length."
    end
  end
  def hashpass(_password, _salt) do
    raise ArgumentError, message: "Wrong type. The password and salt need to be strings."
  end

  def hashpw(password, salt) do
    [_, prefix, log_rounds, salt] = String.split(salt, "$")
    bcrypt(password, salt, prefix, log_rounds)
    |> :erlang.list_to_binary
    |> fmt_hash(salt, log_rounds)
  end

  defp fmt_salt(salt, log_rounds) do
    if log_rounds < 10, do: prefix = "$2b$0", else: prefix = "$2b$"
    "#{prefix}#{log_rounds}$#{Tools.bcrypt64enc(salt)}"
  end
  defp fmt_hash(hash, salt, log_rounds) do
    if log_rounds < 10, do: prefix = "$2b$0", else: prefix = "$2b$"
    "#{prefix}#{log_rounds}$#{salt}#{Tools.bcrypt64enc(hash)}"
  end

  defp bcrypt(key, salt, prefix, log_rounds) do
    key_len = byte_size(key) + 1
    if prefix == "2b" and key_len > 73, do: key_len = 73
    {key, salt, rounds} = prepare_keys(key, salt, String.to_integer(log_rounds))
    bf_init(key, key_len, salt)
    |> expand_keys(key, key_len, salt, rounds)
    |> bf_encrypt
  end

  defp prepare_keys(key, salt, log_rounds) when log_rounds in 4..31 do
    key = :erlang.binary_to_list(key)
    salt = Tools.bcrypt64dec(salt) |> :erlang.binary_to_list
    {key, salt, bsl(1, log_rounds)}
  end
  defp prepare_keys(_, _, _) do
    raise ArgumentError, message: "Wrong number of rounds."
  end

  defp expand_keys(state, _key, _key_len, _salt, 0), do: state
  defp expand_keys(state, key, key_len, salt, rounds) do
    bf_expand(state, key, key_len, salt)
    |> expand_keys(key, key_len, salt, rounds - 1)
  end

  @doc """
  Hash the password with a salt which is randomly generated.

  There is an option to change the log_rounds parameter, which
  affects the complexity of the generation of the password hash.
  """
  def hashpwsalt(password, log_rounds \\ Config.bcrypt_log_rounds) do
    hashpass(password, gen_salt(log_rounds))
  end

  @doc """
  Check the password.

  The check is performed in constant time to avoid timing attacks.
  """
  def checkpw(password, hash) do
    [_, prefix, log_rounds, salt_hash] = String.split(hash, "$")
    {salt, hash} = String.split_at(salt_hash, 22)
    bcrypt(password, salt, prefix, log_rounds)
    |> Tools.secure_check(:erlang.binary_to_list(hash))
  end

  @doc """
  Perform a dummy check for a user that does not exist.
  This always returns false. The reason for implementing this check is
  in order to make user enumeration by timing responses more difficult.
  """
  def dummy_checkpw do
    hashpwsalt("password")
    false
  end
end
