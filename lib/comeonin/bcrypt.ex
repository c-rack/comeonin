defmodule Comeonin.Bcrypt do
  @moduledoc """
  Module to handle bcrypt authentication.

  To generate a password hash, use the `hashpwsalt` function:

    Comeonin.Bcrypt.hashpwsalt("hard to guess")

  To check the password against a password hash, use the `checkpw` function:

    Comeonin.Bcrypt.checkpw("hard to guess", stored_hash)

  There is also a `dummy_checkpw`, which can be used to stop an attacker guessing
  a username by timing the responses.

  See the documentation for each function for more details.

  Most users will not need to use any of the other functions in this module.

  ## Bcrypt

  Bcrypt is a key derivation function for passwords designed by Niels Provos
  and David Mazières. Bcrypt is an adaptive function, which means that it can
  be configured to remain slow and resistant to brute-force attacks even as
  computational power increases.

  This bcrypt implementation is based on the latest OpenBSD version, which
  fixed a small issue that affected some passwords longer than 72 characters.

  The computationally intensive code is run in C, using Erlang NIFs. One concern
  about NIFs is that they block the Erlang VM, and so it is better to make
  sure these functions do not run for too long. This bcrypt implementation
  has been adapted so that each NIF runs for as short a time as possible.
  """

  use Bitwise
  alias Comeonin.Bcrypt.Base64
  alias Comeonin.Config
  alias Comeonin.Tools
  import Comeonin.Gettext

  @on_load {:init, 0}

  def init do
    path = :filename.join(:code.priv_dir(:comeonin), 'bcrypt_nif')
    :ok = :erlang.load_nif(path, 0)
  end

  @doc """
  Generate a salt for use with the `hashpass` function.

  The log_rounds parameter determines the computational complexity
  of the generation of the password hash. Its default is 12, the minimum is 4,
  and the maximum is 31.
  """
  def gen_salt(log_rounds) when log_rounds in 4..31 do
    :crypto.strong_rand_bytes(16) |> :binary.bin_to_list |> fmt_salt(zero_str(log_rounds))
  end
  def gen_salt(_), do: gen_salt(Config.bcrypt_log_rounds)
  def gen_salt, do: gen_salt(Config.bcrypt_log_rounds)

  @doc """
  Hash the password using bcrypt.
  """
  def hashpass(password, salt) when is_binary(salt) and is_binary(password) do
    if byte_size(salt) == 29 do
      hashpw(:binary.bin_to_list(password), :binary.bin_to_list(salt))
    else
      raise ArgumentError, message: gettext "The salt is the wrong length."
    end
  end
  def hashpass(_password, _salt) do
    raise ArgumentError, message: gettext "Wrong type. The password and salt need to be strings."
  end

  @doc """
  Hash the password with a salt which is randomly generated.

  To change the complexity (and the time taken) of the  password hash
  calculation, you need to change the value for `bcrypt_log_rounds`
  in the config file.
  """
  def hashpwsalt(password) do
    hashpass(password, gen_salt(Config.bcrypt_log_rounds))
  end

  @doc """
  Check the password.

  The check is performed in constant time to avoid timing attacks.
  """
  def checkpw(password, hash) when is_binary(password) and is_binary(hash) do
    hashpw(:binary.bin_to_list(password), :binary.bin_to_list(hash))
    |> Tools.secure_check(hash)
  end
  def checkpw(_password, _hash) do
    raise ArgumentError, message: gettext "Wrong type. The password and hash need to be strings."
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

  @doc """
  Initialize the P-box and S-box tables with the digits of Pi,
  and then start the key expansion process.
  """
  def bf_init(key, key_len, salt)
  def bf_init(_, _, _), do: exit(:nif_library_not_loaded)

  @doc """
  The main key expansion function. This function is called
  2^log_rounds times.
  """
  def bf_expand(state, key, key_len, salt)
  def bf_expand(_, _, _, _), do: exit(:nif_library_not_loaded)

  @doc """
  Encrypt and return the hash.
  """
  def bf_encrypt(state)
  def bf_encrypt(_), do: exit(:nif_library_not_loaded)

  defp hashpw(password, salt) do
    [prefix, log_rounds, salt] = Enum.take(salt, 29) |> :string.tokens('$')
    bcrypt(password, salt, prefix, log_rounds)
    |> fmt_hash(salt, prefix, zero_str(log_rounds))
  end

  defp bcrypt(key, salt, prefix, log_rounds) do
    key_len = length(key) + 1
    if prefix == "2b" and key_len > 73, do: key_len = 73
    {salt, rounds} = prepare_keys(salt, List.to_integer(log_rounds))
    bf_init(key, key_len, salt)
    |> expand_keys(key, key_len, salt, rounds)
    |> bf_encrypt
  end

  defp prepare_keys(salt, log_rounds) when log_rounds in 4..31 do
    {Base64.decode(salt), bsl(1, log_rounds)}
  end
  defp prepare_keys(_, _) do
    raise ArgumentError, message: gettext "Wrong number of rounds."
  end

  defp expand_keys(state, _key, _key_len, _salt, 0), do: state
  defp expand_keys(state, key, key_len, salt, rounds) do
    bf_expand(state, key, key_len, salt)
    |> expand_keys(key, key_len, salt, rounds - 1)
  end

  defp zero_str(log_rounds) do
    if log_rounds < 10, do: "0#{log_rounds}", else: "#{log_rounds}"
  end
  defp fmt_salt(salt, log_rounds) do
    "$2b$#{log_rounds}$#{Base64.encode(salt)}"
  end
  defp fmt_hash(hash, salt, prefix, log_rounds) do
    "$#{prefix}$#{log_rounds}$#{salt}#{Base64.encode(hash)}"
  end
end
