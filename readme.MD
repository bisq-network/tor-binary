# Tor Binary files

Package native Tor files from [Tor Browser project](https://www.torproject.org/) expert bundles in a way that can be used by Java projects. Use the SHA256 hashes for checksum verification.

# Process

1. Fetch Tor expert bundles in parallel
2. Verify checksum
3. Package the `tor/` directory from each bundle as `tor.tar.xz`
4. Extract geoip files from the Linux x86_64 expert bundle

# Update to new version

1. Replace `torbrowser.version` with the target Tor Browser bundle version in the [build file](build.xml) and the [Maven file](pom.xml)
2. Find out which `tor binary version` is used in that Tor Browser release. Use that as the Maven project version.
3. Set the `tor-binary version` in following Maven files:
   - [pom.xml](pom.xml)
   - [tor-binary-geoip/pom.xml](tor-binary-geoip/pom.xml)
   - [tor-binary-linux32/pom.xml](tor-binary-linux32/pom.xml)
   - [tor-binary-linux64/pom.xml](tor-binary-linux64/pom.xml)
   - [tor-binary-macos/pom.xml](tor-binary-macos/pom.xml)
   - [tor-binary-macos-aarch64/pom.xml](tor-binary-macos-aarch64/pom.xml)
   - [tor-binary-resources/pom.xml](tor-binary-resources/pom.xml)
   - [tor-binary-windows/pom.xml](tor-binary-windows/pom.xml)
   - [tor-binary-windows64/pom.xml](tor-binary-windows64/pom.xml)
4. Get the hash values of the new version from https://archive.torproject.org/tor-package-archive/torbrowser/[torbrowser.version]/sha256sums-signed-build.txt and update the files inside [tor-binary-resources/checksums](tor-binary-resources/checksums). Alternatively, run `ant -f build.xml` to verify signatures and regenerate the checksum files.
5. Verify the Tor expert bundle PGP signatures with Maven:
   ```
   mvn -N -Pcheck-pgp-signatures verify
   ```

Tor Browser versions can be found here: https://archive.torproject.org/tor-package-archive/torbrowser/[torbrowser.version]

# Pre-requisites

- GPG, when checking PGP signatures with Maven or refreshing checksums with `build.xml`
- tar with gzip/xz support
- network access to `archive.torproject.org` and `keys.openpgp.org` for PGP signature checks


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
