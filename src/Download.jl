module Download

import Pkg.GitTools

import HTTP
import Tar
import SHA: sha256

"""
    download(url, [ path ];
        [ file_hash = <sha256> ]) -> path

Download the file at `url`, saving the resulting download at `path`. If `path`
is not provided, the file is saved to a temporary location which is returned. If
the `file_hash` keyword argument is provided, the SHA2-256 hash of the
downloaded file is computed and if it does not match the provided hash value,
the path is deleted and an error is thrown.
"""
function download(
    url :: AbstractString,
    path :: AbstractString = tempname();
    file_hash :: Union{AbstractString, Nothing} = nothing,
)
    file_hash = normalize_file_hash(file_hash)
    if file_hash !== nothing && isfile(path)
        hash_file(path) == file_hash && return path
        rm(path)
    end
    # TODO: should write directly to path but can't because of
    # https://github.com/JuliaWeb/HTTP.jl/issues/526
    response = HTTP.get(url, status_exception=false)
    try write(path, response.body)
    catch
        rm(path, force=true)
        rethrow()
    end
    if response.status != 200
        # TODO: handle 401 auth error
        rm(path, force=true)
        error("Download $url failed, status code $(response.status)")
    end
    if file_hash !== nothing
        calc_hash = hash_file(path)
        if calc_hash != file_hash
            msg  = "File hash mismatch!\n"
            msg *= "  Expected SHA2-256: $file_hash\n"
            msg *= "  Received SHA2-256: $calc_hash"
            rm(path)
            error(msg)
        end
    end
    return path
end

"""
    download_unpack(url, [ path ];
        [ file_hash = <sha256> ], [ tree_hash = <sha1> ]) -> path

Download the file at `url`, saving the resulting download at `path`. If `path`
is not provided, the file is saved to a temporary location which is returned. If
the `file_hash` keyword argument is provided, the SHA2-256 hash of the
downloaded file is computed and if it does not match the provided hash value,
the path is deleted and an error is thrown.
"""
function download_unpack(
    url :: AbstractString,
    path :: AbstractString = tempname();
    file_hash :: Union{AbstractString, Nothing} = nothing,
    tree_hash :: Union{AbstractString, Nothing} = nothing,
)
    tree_hash = normalize_tree_hash(tree_hash)
    if tree_hash !== nothing && isdir(path)
        hash_tree(path) == tree_hash && return path
        rm(path, recursive=true)
    end
    tarball = download(url, file_hash = file_hash)
    open(`gzcat $tarball`) do io
        Tar.extract(io, path)
    end
    if tree_hash !== nothing
        calc_hash = hash_tree(path)
        if calc_hash != tree_hash
            msg  = "Tree hash mismatch!\n"
            msg *= "  Expected SHA1: $tree_hash\n"
            msg *= "  Received SHA1: $calc_hash"
            rm(path, recursive=true)
            error(msg)
        end
    end
    return path
end

# file hashing

function hash_file(path::AbstractString)
    open(path) do io
        bytes2hex(sha256(io))
    end
end

function hash_tree(path::AbstractString)
    bytes2hex(GitTools.tree_hash(path))
end

# hash string normalization & validity checking

normalize_file_hash(path) = normalize_hash(256, path) # SHA256
normalize_tree_hash(path) = normalize_hash(160, path) # SHA1

normalize_hash(bits::Int, ::Nothing) = nothing
normalize_hash(bits::Int, hash::AbstractString) = normalize_hash(bits, String(hash))

function normalize_hash(bits::Int, hash::String)
    bits % 16 == 0 ||
        throw(ArgumentError("Invalid number of bits for a hash: $bits"))
    len = bits >> 2
    len_ok = length(hash) == len
    chars_ok = occursin(r"^[0-9a-f]*$"i, hash)
    if !len_ok || !chars_ok
        msg = "Hash value must be $len hexadecimal characters ($bits bits); "
        msg *= "Given hash value "
        if !chars_ok
            if isascii(hash)
                msg *= "contains non-hexadecimal characters"
            else
                msg *= "is non-ASCII"
            end
        end
        if !chars_ok && !len_ok
            msg *= " and "
        end
        if !len_ok
            msg *= "has the wrong length ($(length(hash)))"
        end
        msg *= ": $(repr(hash))"
        throw(ArgumentError(msg))
    end
    return lowercase(hash)
end

end # module
