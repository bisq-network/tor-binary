# Tor Binary files

Package native Tor files from [Tor Browser project](https://www.torproject.org/) expert bundles in a way that can be used by Java projects. Use the SHA256 hashes for checksum verification.

# Process

1. Fetch Tor expert bundles in parallel
2. Verify checksum and the tor version of each bundle
3. Package the `tor/` directory from each bundle as `tor.tar.xz`
4. Extract geoip files from the Linux x86_64 expert bundle

# Update to new version

1. Replace `torbrowser.version` with the target Tor Browser bundle version in the root [Maven file](pom.xml)
2. Find out which `tor binary version` is used in that Tor Browser release. Use that as the Maven project version.
   The [download page](https://www.torproject.org/download/tor/) lists it next to each release, for example
   `15.0.23 (tor 0.4.9.12)`. The build fails when the tor executable in any bundle reports another version.
3. Set the `tor-binary version` in the following Maven files:
   - [pom.xml](pom.xml)
   - [tor-binary-geoip/pom.xml](tor-binary-geoip/pom.xml)
   - [tor-binary-linux32/pom.xml](tor-binary-linux32/pom.xml)
   - [tor-binary-linux64/pom.xml](tor-binary-linux64/pom.xml)
   - [tor-binary-macos/pom.xml](tor-binary-macos/pom.xml)
   - [tor-binary-macos-aarch64/pom.xml](tor-binary-macos-aarch64/pom.xml)
   - [tor-binary-resources/pom.xml](tor-binary-resources/pom.xml)
   - [tor-binary-windows/pom.xml](tor-binary-windows/pom.xml)
   - [tor-binary-windows64/pom.xml](tor-binary-windows64/pom.xml)
4. Replace the tracked checksum manifest and its detached signature with the files published for the new
   version under `torbrowser.checksum.source.url`:
   ```
   curl --fail --remote-name-all \
       https://archive.torproject.org/tor-package-archive/torbrowser/15.0.23/{sha256sums-signed-build.txt,sha256sums-signed-build.txt.asc}
   mv sha256sums-signed-build.txt sha256sums-signed-build.txt.asc tor-binary-resources/checksums/
   ```
   Store the manifest exactly as published, with all its entries and without adding anything. It has to stay
   byte identical to the upstream file, otherwise its signature no longer verifies.
5. Verify the manifest and the expert bundles:
   ```
   mvn -N -Pcheck-pgp-signatures verify
   ```
6. Build all artifacts:
   ```
   mvn clean install
   ```

`mvn -N -Pcheck-pgp-signatures verify` performs the checks that need network access and GPG:

- the tracked manifest carries a valid signature made with the Tor Browser Developers key
  `EF6E286DDA85EA2A4BA7DE684E2C6E8793298290`, which is pinned in [verification.xml](verification.xml),
- the tracked manifest is byte for byte the file that is published for the configured `torbrowser.version`,
- every expert bundle of that version carries a valid signature made with the same key.

The pinned key is fetched from `pgp.signature.keyserver` at the start of each run into a keyring that is
created for that run and holds nothing else, so no other key can satisfy a verification. The run therefore
needs the keyserver to be reachable. Fetching every run is also what makes a revocation visible: a key that
is already present is never refreshed on its own. A keyserver that serves a certificate with the revocation
removed still hides it, which no verifier can detect.

`ant -f build.xml` runs the same checks, plus the digest and tor version checks below, and builds no artifact.

`mvn clean install` needs neither GPG nor the keyserver. It verifies every downloaded expert bundle against
the digest pinned in the tracked manifest and fails when an entry is missing or a digest differs, so no
unverified bundle is ever packaged. It then reads the version that tor compiles into the tor executable of
every bundle and fails when it differs from the Maven project version. An artifact therefore cannot be
published under a tor version that it does not contain.

[tools/verification-selftest.sh](tools/verification-selftest.sh) checks the rules themselves against local
fixtures and its own throwaway test keys. It covers the digest rules, the tor version rules, the signature
rules, including a signature made with an unrelated key, a revoked key, an expired key and content changed
after signing, and the key fetch against a stub keyserver on the loopback interface. It needs no network
access and never touches your own GPG keyring.

Tor Browser versions can be found here: https://archive.torproject.org/tor-package-archive/torbrowser/[torbrowser.version]

# Continuous integration

[.github/workflows/build.yml](.github/workflows/build.yml) runs three jobs on GitHub Actions for every push and
pull request:

- `Build`: `mvn clean install`, including the digest and tor version checks
- `Verify signatures`: `mvn -N -Pcheck-pgp-signatures verify`, which needs the keyserver
- `Verification self-test`: `tools/verification-selftest.sh`

A pull request is checked with the workflow and the verification rules from its own branch. A passing run
therefore does not show that changes to `verification.xml`, `build.xml`, the POM files or the workflow are
correct. Review such changes separately.

# Pre-requisites

- GPG, when checking signatures with `mvn -Pcheck-pgp-signatures` or `build.xml`, and for the self-test
- tar with gzip/xz support
- network access to `archive.torproject.org` for the bundles, and to the configured keyserver
  (`hkps://keys.openpgp.org`) for the Tor signing key


# Install
Change in pom to get the desired Tor Browser bundle version

```<torbrowser.version>your TorBrowserBundle version here</torbrowser.version>```

run ```mvn install```

alternatively, you can source jitpack.io:

Maven:
```
    <repositories>
        <repository>
            <id>jitpack.io</id>
            <url>https://jitpack.io</url>
        </repository>
        ...
    </repositories>
```

Gradle:
```
    repositories {
        maven { url 'https://jitpack.io' }
        ...
    }
```


# Usage

Each platform artifact is a JAR containing `native/.../tor.tar.xz`:

```
<dependency>
    <groupId>com.github.bisq-network.tor-binary</groupId>
    <artifactId>tor-binary-linux32</artifactId>
    <version>${tor.version}</version>
</dependency>
```
```
<dependency>
    <groupId>com.github.bisq-network.tor-binary</groupId>
    <artifactId>tor-binary-linux64</artifactId>
    <version>${tor.version}</version>
</dependency>
```
```
<dependency>
    <groupId>com.github.bisq-network.tor-binary</groupId>
    <artifactId>tor-binary-macos</artifactId>
    <version>${tor.version}</version>
</dependency>
```
```
<dependency>
    <groupId>com.github.bisq-network.tor-binary</groupId>
    <artifactId>tor-binary-macos-aarch64</artifactId>
    <version>${tor.version}</version>
</dependency>
```
```
<dependency>
    <groupId>com.github.bisq-network.tor-binary</groupId>
    <artifactId>tor-binary-windows</artifactId>
    <version>${tor.version}</version>
</dependency>
```
```
<dependency>
    <groupId>com.github.bisq-network.tor-binary</groupId>
    <artifactId>tor-binary-windows64</artifactId>
    <version>${tor.version}</version>
</dependency>
```

you may want to unpack these dependencies if required using
```
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-dependency-plugin</artifactId>
    <executions>
        <execution>
            <id>copy</id>
            <phase>generate-resources</phase>
            <goals>
                <goal>unpack</goal>
            </goals>
            <configuration>
                <artifactItems>
                    <artifactItem>
                        <groupId>com.github.bisq-network.tor-binary</groupId>
                        <artifactId>tor-binary-linux32</artifactId>
                        <version>${tor.version}</version>
                        <overWrite>false</overWrite>
                        <includes>native/linux/x86/tor.tar.xz</includes>
                        <outputDirectory>${project.build.directory}/classes</outputDirectory>
                    </artifactItem>
                 </artifactItems>
            </configuration>
        </execution>
    </executions>
</plugin>
```
