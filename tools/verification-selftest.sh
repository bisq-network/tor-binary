#!/usr/bin/env bash
#
# Exercises the verification rules in verification.xml with small local fixtures, so the
# failure paths can be checked without downloading the real Tor expert bundles and without
# access to the Tor signing key. Run it after changing verification.xml.
#
# Usage: tools/verification-selftest.sh
# Requires: ant (override with ANT=/path/to/ant), gpg, sha256sum, tar with gzip support
#
# All GPG work happens in throwaway directories created by this script. The user's own
# keyring is never read or modified, and no key is published anywhere.

set -o nounset

project_root="$(cd "$(dirname "$0")/.." && pwd)"
ant_command="${ANT:-ant}"
torbrowser_version="15.0.25"
tor_fingerprint="EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"
platforms=(windows-i686 windows-x86_64 macos-x86_64 macos-aarch64 linux-i686 linux-x86_64)

work_directory="$(mktemp -d)"
trap 'gpgconf --homedir "$work_directory/signer" --kill all >/dev/null 2>&1; gpgconf --homedir "$work_directory/fetched-keyring" --kill all >/dev/null 2>&1; [ -n "${keyserver_pid:-}" ] && kill "$keyserver_pid" >/dev/null 2>&1; rm -rf "$work_directory"' EXIT

failures=0

pass() { echo "PASS  $1"; }
fail() {
    echo "FAIL  $1: $2"
    [ -n "${3:-}" ] && echo "$3" | sed 's/^/      /'
    failures=$((failures + 1))
}

# ---------------------------------------------------------------------------------------
# Digest rules
# ---------------------------------------------------------------------------------------

# Writes six distinct fixture bundles and a manifest listing all of them.
create_digest_fixture() {
    local case_directory="$work_directory/digest-$1"

    mkdir -p "$case_directory/bundles"
    : > "$case_directory/manifest.txt"
    for platform in "${platforms[@]}"; do
        local bundle="tor-expert-bundle-$platform-$torbrowser_version.tar.gz"
        echo "content of $bundle" > "$case_directory/bundles/$bundle"
        echo "$(sha256sum "$case_directory/bundles/$bundle" | cut -d' ' -f1)  $bundle" \
            >> "$case_directory/manifest.txt"
    done
    echo "$case_directory"
}

run_digest_verification() {
    "$ant_command" -f "$project_root/verification.xml" verify-bundle-checksums \
        "-Dbundle.directory=$1/bundles" \
        "-Dchecksum.file=$1/manifest.txt" \
        "-Dtorbrowser.version=$torbrowser_version" 2>&1
}

expect_digest_success() {
    local output
    output="$(run_digest_verification "$2")"
    if [ $? -eq 0 ]; then pass "$1"; else fail "$1" "verification failed although the fixture is valid" "$output"; fi
}

expect_digest_failure() {
    local output
    output="$(run_digest_verification "$2")"
    if [ $? -eq 0 ]; then
        fail "$1" "verification succeeded although it must not"
    elif ! echo "$output" | grep -q "$3"; then
        fail "$1" "expected message '$3' not reported" "$output"
    else
        pass "$1"
    fi
}

matching_digests="$(create_digest_fixture matching)"
expect_digest_success "every digest matches" "$matching_digests"

modified_bundle="$(create_digest_fixture modified)"
echo "tampered" > "$modified_bundle/bundles/tor-expert-bundle-linux-x86_64-$torbrowser_version.tar.gz"
expect_digest_failure "modified bundle" "$modified_bundle" "Checksum verification failed"

missing_entry="$(create_digest_fixture missing)"
grep -v "tor-expert-bundle-macos-aarch64-$torbrowser_version.tar.gz" \
    "$missing_entry/manifest.txt" > "$missing_entry/manifest.trimmed"
mv "$missing_entry/manifest.trimmed" "$missing_entry/manifest.txt"
expect_digest_failure "entry missing from the manifest" "$missing_entry" "No checksum found"

foreign_entry="$(create_digest_fixture foreign)"
sed -i.bak "s|tor-expert-bundle-windows-i686-$torbrowser_version.tar.gz|tor-expert-bundle-windows-i686-15.0.20.tar.gz|" \
    "$foreign_entry/manifest.txt"
expect_digest_failure "entry for another Tor Browser version" "$foreign_entry" "No checksum found"

duplicate_entry="$(create_digest_fixture duplicate)"
grep "tor-expert-bundle-linux-i686-$torbrowser_version.tar.gz" \
    "$duplicate_entry/manifest.txt" | sed 's/^./0/' >> "$duplicate_entry/manifest.txt"
expect_digest_failure "duplicate entry for one bundle" "$duplicate_entry" "More than one checksum entry"

tab_separator="$(create_digest_fixture tab)"
sed -i.bak "s|  tor-expert-bundle-linux-i686|\ttor-expert-bundle-linux-i686|" "$tab_separator/manifest.txt"
expect_digest_failure "tab instead of two spaces as the separator" "$tab_separator" "No checksum found"

malformed_entry="$(create_digest_fixture malformed-entry)"
printf 'not-a-digest  tor-expert-bundle-linux-i686-%s.tar.gz\n' "$torbrowser_version" \
    >> "$malformed_entry/manifest.txt"
expect_digest_success "malformed additional entry does not override a valid checksum" "$malformed_entry"

sed -i.bak '/^[0-9a-f]\{64\}  tor-expert-bundle-linux-i686-/d' "$malformed_entry/manifest.txt"
expect_digest_failure "malformed entry cannot replace a valid checksum" "$malformed_entry" "No checksum found"

identical_duplicate="$(create_digest_fixture identical-duplicate)"
grep "tor-expert-bundle-windows-x86_64-$torbrowser_version.tar.gz" \
    "$identical_duplicate/manifest.txt" > "$identical_duplicate/repeated"
cat "$identical_duplicate/repeated" >> "$identical_duplicate/manifest.txt"
expect_digest_failure "the same entry twice" "$identical_duplicate" "More than one checksum entry"

missing_bundle="$(create_digest_fixture missing-bundle)"
rm "$missing_bundle/bundles/tor-expert-bundle-linux-i686-$torbrowser_version.tar.gz"
expect_digest_failure "bundle file missing from the download directory" "$missing_bundle" "Could not find file"

windows_line_endings="$(create_digest_fixture crlf)"
sed -i.bak 's/$/\r/' "$windows_line_endings/manifest.txt"
expect_digest_success "manifest with CRLF line endings" "$windows_line_endings"

# ---------------------------------------------------------------------------------------
# Tor version rules
# ---------------------------------------------------------------------------------------

build_version=" (on Tor 0.4.9.13 78923280eed3eff6)"

tor_executable_of() {
    case "$1" in
        windows-*) echo "tor/tor.exe" ;;
        *) echo "tor/tor" ;;
    esac
}

# write_tor_executable <file> [build version string...]
# Like the real executable, the stand-in also names unrelated versions and contains bytes
# that a line-based reader or Java's regular expressions treat as line terminators.
write_tor_executable() {
    local file="$1"
    shift
    mkdir -p "$(dirname "$file")"
    {
        printf '\177ELF\000\n\r\205'
        printf '%s\000' "0.4.9.1-alpha" "Tor 0.1.2.17 and later" "tor 0.4.9.11" "(on Tor unknown)"
        for build_version_string in "$@"; do
            printf '%s\000\n\205' "$build_version_string"
        done
        printf 'end\000'
    } > "$file"
}

# write_version_bundle <case directory> <platform> <executable> [build version string...]
write_version_bundle() {
    local case_directory="$1" platform="$2" executable="$3"
    shift 3
    local content="$case_directory/content-$platform"
    rm -rf "$content"
    write_tor_executable "$content/$executable" "$@"
    tar -czf "$case_directory/bundles/tor-expert-bundle-$platform-$torbrowser_version.tar.gz" -C "$content" tor
}

# create_version_fixture <case> [build version string...]
# Writes the six bundles, each with a tor executable holding the given build version strings.
create_version_fixture() {
    local case_directory="$work_directory/version-$1"
    shift
    mkdir -p "$case_directory/bundles"
    for platform in "${platforms[@]}"; do
        write_version_bundle "$case_directory" "$platform" "$(tor_executable_of "$platform")" "$@"
    done
    echo "$case_directory"
}

run_version_verification() {
    "$ant_command" -f "$project_root/verification.xml" verify-bundle-tor-versions \
        "-Dbundle.directory=$1/bundles" \
        "-Dtorbrowser.version=$torbrowser_version" \
        "-Dtor.version=$2" 2>&1
}

# expect_version_success <name> <fixture> <declared version>
expect_version_success() {
    local output
    output="$(run_version_verification "$2" "$3")"
    if [ $? -eq 0 ]; then pass "$1"; else fail "$1" "verification failed although the fixture is valid" "$output"; fi
}

# expect_version_failure <name> <fixture> <declared version> <expected message>
expect_version_failure() {
    local output
    output="$(run_version_verification "$2" "$3")"
    if [ $? -eq 0 ]; then
        fail "$1" "verification succeeded although it must not" "$output"
    elif ! echo "$output" | grep -qF "$4"; then
        fail "$1" "expected message '$4' not reported" "$output"
    else
        pass "$1"
    fi
}

matching_versions="$(create_version_fixture matching "$build_version")"
expect_version_success "every tor executable reports the declared version" "$matching_versions" 0.4.9.13

# Tor Browser 15.0.23 contains tor 0.4.9.13; a different declared project version must fail.
expect_version_failure "declared version differs from the reported one" "$matching_versions" 0.4.9.12 \
    "reports tor 0.4.9.13, but the Maven project version declares tor 0.4.9.12"

expect_version_failure "declared version is the start of the reported one" "$matching_versions" 0.4.9.1 \
    "reports tor 0.4.9.13, but the Maven project version declares tor 0.4.9.1"

# The six bundle names and executable names are built inside verify-bundle-tor-versions, so
# each bundle gets a case of its own.
for platform in "${platforms[@]}"; do
    single_mismatch="$(create_version_fixture "mismatch-$platform" "$build_version")"
    write_version_bundle "$single_mismatch" "$platform" "$(tor_executable_of "$platform")" \
        " (on Tor 0.4.9.11 f3d28b2e0978ca07)"
    expect_version_failure "only the $platform executable reports another version" "$single_mismatch" 0.4.9.13 \
        "$(tor_executable_of "$platform") in tor-expert-bundle-$platform-$torbrowser_version.tar.gz reports tor 0.4.9.11"
done

without_revision="$(create_version_fixture without-revision " (on Tor 0.4.9.13)")"
expect_version_success "build version without a git revision" "$without_revision" 0.4.9.13

suffixed_version="$(create_version_fixture suffixed " (on Tor 0.4.9.13-dev 78923280eed3eff6)")"
expect_version_failure "reported version with a suffix" "$suffixed_version" 0.4.9.13 \
    "reports tor 0.4.9.13-dev, but the Maven project version declares tor 0.4.9.13"

repeated_version="$(create_version_fixture repeated "$build_version" "$build_version")"
expect_version_success "the same build version twice" "$repeated_version" 0.4.9.13

two_versions="$(create_version_fixture two-versions "$build_version" " (on Tor 0.4.9.12 0123456789abcdef)")"
expect_version_failure "two different build versions" "$two_versions" 0.4.9.13 \
    "reports more than one tor build version: 0.4.9.12 0.4.9.13"

no_version="$(create_version_fixture no-version)"
expect_version_failure "no build version string" "$no_version" 0.4.9.13 "reports no tor build version"

misnamed_executable="$(create_version_fixture misnamed "$build_version")"
write_version_bundle "$misnamed_executable" windows-x86_64 tor/tor "$build_version"
expect_version_failure "Windows bundle without tor.exe" "$misnamed_executable" 0.4.9.13 \
    "tor-expert-bundle-windows-x86_64-$torbrowser_version.tar.gz does not contain tor/tor.exe"

missing_version_bundle="$(create_version_fixture missing-bundle "$build_version")"
rm "$missing_version_bundle/bundles/tor-expert-bundle-linux-i686-$torbrowser_version.tar.gz"
expect_version_failure "bundle file missing from the download directory" "$missing_version_bundle" 0.4.9.13 \
    "Could not find"

# ---------------------------------------------------------------------------------------
# Signature rules
#
# The keyring passed to verification.xml holds only public keys, which is what the build
# produces when it fetches the pinned key. pgp.keyring.prepared keeps the fetch out of the
# way so these cases run offline with the keys created here.
# ---------------------------------------------------------------------------------------

signer_home="$work_directory/signer"
keyring="$work_directory/keyring"
mkdir -p "$signer_home" "$keyring"
chmod 700 "$signer_home" "$keyring"

signer_gpg() { gpg --homedir "$signer_home" --batch --no-tty --yes --no-auto-check-trustdb "$@"; }

# create_key <user id> [expiry] [faked time] -> fingerprint
create_key() {
    local user_id="$1" expiry="${2:-never}" faked_time="${3:-}"
    local time_option=()
    [ -n "$faked_time" ] && time_option=(--faked-system-time "$faked_time")
    signer_gpg "${time_option[@]}" --passphrase '' --quick-generate-key \
        "$user_id" default default "$expiry" >/dev/null 2>&1
    signer_gpg --list-keys --with-colons "$user_id" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}'
}

# sign_as <fingerprint> <file> [faked time]
sign_as() {
    local fingerprint="$1" file="$2" faked_time="${3:-}"
    local time_option=()
    [ -n "$faked_time" ] && time_option=(--faked-system-time "$faked_time")
    signer_gpg "${time_option[@]}" --detach-sign --armor --local-user "$fingerprint" \
        --output "$file.asc" "$file" >/dev/null 2>&1
}

publish_key() {
    signer_gpg --export --armor "$1" 2>/dev/null \
        | gpg --homedir "$keyring" --batch --no-auto-check-trustdb --import >/dev/null 2>&1
}

# run_signature_verification <file> <pinned fingerprint> [published manifest url]
# The published manifest defaults to the file itself, so every case also exercises the
# comparison with the published source.
run_signature_verification() {
    "$ant_command" -f "$project_root/verification.xml" verify-checksum-manifest \
        "-Dchecksum.file=$1" \
        "-Dchecksum.source.url=${3:-file://$1}" \
        "-Dpgp.signing.key.fingerprint=$2" \
        "-Dpgp.keyring.directory=$keyring" \
        -Dpgp.keyring.prepared=true \
        -Dpgp.signature.keyserver=none.invalid 2>&1
}

expect_signature_success() {
    local output
    output="$(run_signature_verification "$2" "$3" "${4:-}")"
    if [ $? -eq 0 ]; then pass "$1"; else fail "$1" "verification failed although the signature is valid" "$output"; fi
}

# expect_signature_failure <name> <file> <pinned fingerprint> <expected message> [url]
expect_signature_failure() {
    local output
    output="$(run_signature_verification "$2" "$3" "${5:-}")"
    if [ $? -eq 0 ]; then
        fail "$1" "verification succeeded although it must not" "$output"
    elif ! echo "$output" | grep -q "$4"; then
        fail "$1" "expected message '$4' not reported" "$output"
    else
        pass "$1"
    fi
}

printf 'manifest payload\n' > "$work_directory/manifest.txt"

expected_key="$(create_key "Expected signer <expected@example.invalid>")"
publish_key "$expected_key"
sign_as "$expected_key" "$work_directory/manifest.txt"
expect_signature_success "signature made with the pinned key" \
    "$work_directory/manifest.txt" "$expected_key"

# The same file and signature, judged against the production fingerprint.
expect_signature_failure "signature made with an unrelated key" \
    "$work_directory/manifest.txt" "$tor_fingerprint" "is not signed by"

# Regression fixture: the user id spells out the status record the check looks for. GPG
# prints the user id inside its GOODSIG record, so a check that searches the whole status
# output instead of matching whole records accepts this signature.
printf 'manifest payload\n' > "$work_directory/crafted.txt"
crafted_key="$(create_key "Review [GNUPG:] VALIDSIG $tor_fingerprint <crafted@example.invalid>")"
publish_key "$crafted_key"
sign_as "$crafted_key" "$work_directory/crafted.txt"
expect_signature_failure "user id spelling out a VALIDSIG record" \
    "$work_directory/crafted.txt" "$tor_fingerprint" "is not signed by"

# Same idea with a Unicode line separator instead of the plain text above. gpg escapes CR and
# LF in status records but passes U+2028 through, and Java counts it as a line terminator, so a
# rule anchored with ^ in multiline mode could be made to see a record of its own here.
printf 'manifest payload\n' > "$work_directory/separator.txt"
separator_key="$(create_key \
    "S <separator@example.invalid>"$'\u2028'"[GNUPG:] VALIDSIG $tor_fingerprint 1 2 3 4 5 6 7 8 $tor_fingerprint")"
publish_key "$separator_key"
sign_as "$separator_key" "$work_directory/separator.txt"
expect_signature_failure "user id with a Unicode line separator before a VALIDSIG record" \
    "$work_directory/separator.txt" "$tor_fingerprint" "is not signed by"

# The production shape: a signing subkey certified by the pinned primary key. GPG names the
# subkey in the first field of the VALIDSIG record and the primary key in the last one.
printf 'manifest payload\n' > "$work_directory/subkey.txt"
subkey_primary="$(create_key "Subkey signer <subkey@example.invalid>")"
signer_gpg --passphrase '' --quick-add-key "$subkey_primary" default sign never >/dev/null 2>&1
subkey_fingerprint="$(signer_gpg --list-keys --with-colons "$subkey_primary" 2>/dev/null \
    | awk -F: '$1=="sub"{capabilities=$12} $1=="fpr" && capabilities ~ /s/ {print $10; exit}')"
publish_key "$subkey_primary"
sign_as "$subkey_primary" "$work_directory/subkey.txt"
expect_signature_success "signature made with a subkey of the pinned key" \
    "$work_directory/subkey.txt" "$subkey_primary"
expect_signature_failure "subkey fingerprint pinned instead of the primary key" \
    "$work_directory/subkey.txt" "$subkey_fingerprint" "is not signed by"

printf 'manifest payload\n' > "$work_directory/tampered.txt"
sign_as "$expected_key" "$work_directory/tampered.txt"
printf 'manifest payload with one more line\n' >> "$work_directory/tampered.txt"
expect_signature_failure "content changed after signing" \
    "$work_directory/tampered.txt" "$expected_key" "exec returned"

printf 'manifest payload\n' > "$work_directory/unknown.txt"
unknown_key="$(create_key "Unpublished signer <unknown@example.invalid>")"
sign_as "$unknown_key" "$work_directory/unknown.txt"
expect_signature_failure "signer key not in the verification keyring" \
    "$work_directory/unknown.txt" "$unknown_key" "exec returned"

printf 'manifest payload\n' > "$work_directory/revoked.txt"
revoked_key="$(create_key "Revoked signer <revoked@example.invalid>")"
publish_key "$revoked_key"
sign_as "$revoked_key" "$work_directory/revoked.txt"
sed 's/^://' "$signer_home/openpgp-revocs.d/$revoked_key.rev" \
    | gpg --homedir "$keyring" --batch --no-auto-check-trustdb --import >/dev/null 2>&1
expect_signature_failure "signing key revoked after signing" \
    "$work_directory/revoked.txt" "$revoked_key" "revoked key"

# Signed while the key was valid, verified after it expired. GPG reports VALIDSIG together
# with EXPKEYSIG here, and the gate stops rather than deciding on its own.
printf 'manifest payload\n' > "$work_directory/expired.txt"
expired_key="$(create_key "Expired signer <expired@example.invalid>" 1d 20250101T000000!)"
publish_key "$expired_key"
sign_as "$expired_key" "$work_directory/expired.txt" 20250101T000000!
expect_signature_failure "signing key expired since signing" \
    "$work_directory/expired.txt" "$expired_key" "expired key"

# The signature says Tor published the manifest, not which release it belongs to.
printf 'a different release\n' > "$work_directory/published.txt"
expect_signature_failure "manifest differs from the published file" \
    "$work_directory/manifest.txt" "$expected_key" "differs from" \
    "file://$work_directory/published.txt"

# ---------------------------------------------------------------------------------------
# Bundle signature rules
#
# The six bundle names are built inside verify-bundle-signatures, so this is the only place
# where a mistake in one of them would show up.
# ---------------------------------------------------------------------------------------

signed_bundles="$work_directory/signed-bundles"
mkdir -p "$signed_bundles"
for platform in "${platforms[@]}"; do
    bundle="tor-expert-bundle-$platform-$torbrowser_version.tar.gz"
    echo "content of $bundle" > "$signed_bundles/$bundle"
    sign_as "$expected_key" "$signed_bundles/$bundle"
done

run_bundle_signature_verification() {
    "$ant_command" -f "$project_root/verification.xml" verify-bundle-signatures \
        "-Dbundle.directory=$signed_bundles" \
        "-Dtorbrowser.version=$torbrowser_version" \
        "-Dpgp.signing.key.fingerprint=$1" \
        "-Dpgp.keyring.directory=$keyring" \
        -Dpgp.keyring.prepared=true \
        -Dpgp.signature.keyserver=none.invalid 2>&1
}

output="$(run_bundle_signature_verification "$expected_key")"
if [ $? -eq 0 ]; then
    pass "every bundle signed with the pinned key"
else
    fail "every bundle signed with the pinned key" "verification failed although the signatures are valid" "$output"
fi

# One bundle re-signed with another key that is present in the keyring.
sign_as "$crafted_key" "$signed_bundles/tor-expert-bundle-macos-aarch64-$torbrowser_version.tar.gz"
output="$(run_bundle_signature_verification "$expected_key")"
if [ $? -eq 0 ]; then
    fail "one bundle signed with another key" "verification succeeded although it must not" "$output"
elif ! echo "$output" | grep -q "is not signed by"; then
    fail "one bundle signed with another key" "expected message 'is not signed by' not reported" "$output"
else
    pass "one bundle signed with another key"
fi

# ---------------------------------------------------------------------------------------
# Key fetch
#
# These cases run the real -fetch-signing-key path against a local stub keyserver, with the
# test key standing in for the pinned key. Skipped when python3 is missing.
# ---------------------------------------------------------------------------------------

keyserver_pid=""
stop_keyserver_stub() {
    if [ -n "$keyserver_pid" ]; then
        kill "$keyserver_pid" >/dev/null 2>&1
        wait "$keyserver_pid" 2>/dev/null
    fi
    keyserver_pid=""
    rm -f "$work_directory/keyserver.port"
}

# start_keyserver_stub <armored key file>
start_keyserver_stub() {
    python3 -c '
import sys, http.server, socketserver
key = open(sys.argv[1], "rb").read()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/pgp-keys")
        self.send_header("Content-Length", str(len(key)))
        self.end_headers()
        self.wfile.write(key)
    def log_message(self, *arguments):
        pass
with socketserver.TCPServer(("127.0.0.1", 0), Handler) as server:
    with open(sys.argv[2], "w") as port_file:
        port_file.write(str(server.server_address[1]))
    server.serve_forever()
' "$1" "$work_directory/keyserver.port" &
    keyserver_pid=$!
    local attempt=0
    while [ ! -s "$work_directory/keyserver.port" ] && [ "$attempt" -lt 100 ] \
        && kill -0 "$keyserver_pid" 2>/dev/null; do
        sleep 0.1
        attempt=$((attempt + 1))
    done
    if [ -s "$work_directory/keyserver.port" ]; then
        return 0
    fi
    fail "stub keyserver" "could not start"
    stop_keyserver_stub
    return 1
}

# run_fetching_verification <file> <pinned fingerprint> <keyserver>
run_fetching_verification() {
    rm -rf "$work_directory/fetched-keyring"
    "$ant_command" -f "$project_root/verification.xml" verify-checksum-manifest \
        "-Dchecksum.file=$1" \
        "-Dchecksum.source.url=file://$1" \
        "-Dpgp.signing.key.fingerprint=$2" \
        "-Dpgp.keyring.directory=$work_directory/fetched-keyring" \
        "-Dpgp.signature.keyserver=$3" 2>&1
}

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP  key fetch cases: python3 is needed for the stub keyserver"
else
    signer_gpg --export --armor "$expected_key" > "$work_directory/expected.asc" 2>/dev/null
    signer_gpg --export --armor "$crafted_key" > "$work_directory/other.asc" 2>/dev/null

    if start_keyserver_stub "$work_directory/expected.asc"; then
        keyserver="hkp://127.0.0.1:$(cat "$work_directory/keyserver.port")"
        output="$(run_fetching_verification "$work_directory/manifest.txt" "$expected_key" "$keyserver")"
        if [ $? -eq 0 ]; then
            pass "key fetched from the keyserver into a new keyring"
        else
            fail "key fetched from the keyserver into a new keyring" "verification failed" "$output"
        fi
        stop_keyserver_stub

        # The same fingerprint is requested, but the keyserver answers with another key.
        if start_keyserver_stub "$work_directory/other.asc"; then
            keyserver="hkp://127.0.0.1:$(cat "$work_directory/keyserver.port")"
            output="$(run_fetching_verification "$work_directory/manifest.txt" "$expected_key" "$keyserver")"
            if [ $? -eq 0 ]; then
                fail "keyserver answers with another key" "verification succeeded although it must not" "$output"
            else
                pass "keyserver answers with another key"
            fi
            stop_keyserver_stub
        fi

        output="$(run_fetching_verification "$work_directory/manifest.txt" "$expected_key" "hkp://127.0.0.1:1")"
        if [ $? -eq 0 ]; then
            fail "keyserver unreachable" "verification succeeded although the key could not be fetched" "$output"
        else
            pass "keyserver unreachable"
        fi
    fi
fi

if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"
