import Foundation

/// One pinned download of the build tools (ADR 0033): fetched only from `url`, refused unless it is exactly `size`
/// bytes with this SHA-256.
struct Artifact: Sendable, Equatable {
    /// The file name it is saved under; wheels keep pip's naming rules.
    var name: String
    var url: URL
    var size: Int64
    var sha256: String
    var headers: [String: String] = [:]
    /// How it is unpacked into the toolchain folder; empty for wheels, which pip installs.
    var unpack: [Unpack] = []

    var isWheel: Bool { name.hasSuffix(".whl") }
}

/// One `/usr/bin/tar` pass: the archive's members matching `include` (all when empty) and not `exclude`, with the
/// first `strip` path components removed, into `into` (relative to the toolchain folder). `*` matches across `/`.
struct Unpack: Sendable, Equatable {
    var into: String
    var strip = 1
    var include: [String] = []
    var exclude: [String] = []
}

/// What the setup step installs, pinned (ADR 0033).
public enum ToolchainPins {
    /// `zsa/qmk_firmware`, branch `firmware25`, and its submodules at the commits that tree records.
    public static let firmwareCommit = "93b2b9ec3368f86c5eb5a2e3f934049f8daef885"
    public static let modulesCommit = "13890cd7856175de20798689d15ba6a46bf0c5c7"
    static let chibiosCommit = "be44b3305f9a9fe5f2f49a4e7b978db322dc463e"
    static let lufaCommit = "549b97320d515bfca2f95c145a67bd13be968faa"
    static let printfCommit = "c2e3b4e10d281e7f0f694d3ecbd9f320977288cc"

    static let all: [Artifact] = tools + wheels + firmware

    static let tools: [Artifact] = [
        // Arm's 12.2.rel1, the release ZSA's firmware is built with. Only what a Cortex-M4F C build needs: the
        // STM32F303 and GD32F303 are both Cortex-M4F with hardware floating point.
        Artifact(
            name: "arm-gnu-toolchain-12.2.rel1-darwin-arm64-arm-none-eabi.tar.xz",
            url: url(
                "https://developer.arm.com/-/media/Files/downloads/gnu/12.2.rel1/binrel/arm-gnu-toolchain-12.2.rel1-darwin-arm64-arm-none-eabi.tar.xz"
            ),
            size: 109_783_356, sha256: "21a9e875250bcb0db8df4cb23dd43c94c00a1d3b98ecba9cdd6ed51586b12248",
            unpack: [
                Unpack(
                    into: "arm",
                    include: [
                        "*/bin/*", "*/libexec/*", "*/lib/gcc/arm-none-eabi/12.2.1/include/*",
                        "*/lib/gcc/arm-none-eabi/12.2.1/include-fixed/*", "*/lib/gcc/arm-none-eabi/12.2.1/thumb/v7e-m+fp/hard/*",
                        "*/arm-none-eabi/include/*", "*/arm-none-eabi/lib/thumb/v7e-m+fp/hard/*", "*/arm-none-eabi/lib/ldscripts/*",
                        // GCC looks up --specs files before it picks the multilib folder, so QMK's link needs this one.
                        "*/arm-none-eabi/lib/nano.specs", "*/lib/bfd-plugins/*",
                    ],
                    exclude: ["*gdb*", "*/cc1plus", "*c++*", "*/arm-none-eabi/include/c++/*"])
            ]),
        Artifact(
            name: "cpython-3.12.15+20261009-aarch64-apple-darwin-install_only_stripped.tar.gz",
            url: url(
                "https://github.com/astral-sh/python-build-standalone/releases/download/20261009/cpython-3.12.15%2B20261009-aarch64-apple-darwin-install_only_stripped.tar.gz"
            ),
            size: 25_030_095, sha256: "233f8e15255b3e1d1fd47ea5dd5230dfed803f371138e896e54d98c60ae19f6f",
            unpack: [Unpack(into: "python")]),
        // GNU make 4.4.1, Homebrew's bottle for macOS 26 (no dependencies). QMK needs make 4; macOS ships 3.81.
        Artifact(
            name: "make-4.4.1.arm64_tahoe.bottle.tar.gz",
            url: url("https://ghcr.io/v2/homebrew/core/make/blobs/sha256:c46713c2347b3af91fc3fb41f215f26341fec6df4687af080e55d921858f06d5"),
            size: 430_188, sha256: "c46713c2347b3af91fc3fb41f215f26341fec6df4687af080e55d921858f06d5",
            // Homebrew's anonymous token for its public bottles.
            headers: ["Authorization": "Bearer QQ=="],
            unpack: [Unpack(into: "make", strip: 2, include: ["*/bin/gmake"])]),
    ]

    /// `qmk` and everything `requirements.txt` lists, resolved for CPython 3.12 on macOS arm64.
    static let wheels: [Artifact] = [
        wheel(
            "argcomplete-3.7.2-py3-none-any.whl", 43294, "6029205678bdd9c1c728a155f5f9ecf5812393f969eef58807641a2bc2aa5b19",
            "46/bd/551ee6af426af84ca33e02622be722925c196608e9127d731ef17c47f06e"),
        wheel(
            "attrs-26.1.0-py3-none-any.whl", 67548, "c647aa4a12dfbad9333ca4e71fe62ddc36f4e63b2d260a37a8b83d2f043ac309",
            "64/b4/17d4b0b2a2dc85a6df63d1157e028ed19f90d4cd97c36717afef2bc2f395"),
        wheel(
            "colorama-0.4.6-py2.py3-none-any.whl", 25335, "4f1d9991f5acc0ca119f9d443620b77f9d6b33703e51011c16baf57afb285fc6",
            "d1/d6/3965ed04c63042e047cb6a3e6ed1a63a35087b6a609aa3a15ed8ac56c221"),
        wheel(
            "dotty_dict-1.3.1-py3-none-any.whl", 7014, "5022d234d9922f13aa711b4950372a06a6d64cb6d6db9ba43d0ba133ebfce31f",
            "1a/91/e0d457ee03ec33d79ee2cd8d212debb1bc21dfb99728ae35efdb5832dc22"),
        // Published only as a py2-tagged wheel, though the code is the same for Python 3; saved with a py3 tag so pip
        // takes it. The hash pins the published file.
        Artifact(
            name: "halo-0.0.31-py3-none-any.whl",
            url: url(
                "https://files.pythonhosted.org/packages/86/e3/065611830ffe8c859130eb99336d26045c477cf55162dd92065e9f1c2938/halo-0.0.31-py2-none-any.whl"
            ),
            size: 11250, sha256: "5350488fb7d2aa7c31a1344120cee67a872901ce8858f60da7946cef96c208ab"),
        wheel(
            "hid-1.0.9-py3-none-any.whl", 4959, "6b9289e00bbc1e1589bec0c7f376a63fe03a4a4a1875575d0ad60e3e11a349f4",
            "b8/c7/f0e1ad95179f44a6fc7a9140be025812cc7a62cf7390442b685a57ee1417"),
        wheel(
            "hjson-3.1.0-py3-none-any.whl", 54018, "65713cdcf13214fb554eb8b4ef803419733f4f5e551047c9b711098ab7186b89",
            "1f/7f/13cd798d180af4bf4c0ceddeefba2b864a63c71645abc0308b768d67bb81"),
        wheel(
            "jsonschema-4.26.0-py3-none-any.whl", 90630, "d489f15263b8d200f8387e64b4c3a75f06629559fb73deb8fdfb525f2dab50ce",
            "69/90/f63fb5873511e014207a475e2bb4e8b2e570d655b00ac19a9a0ca0a385ee"),
        wheel(
            "jsonschema_specifications-2025.9.1-py3-none-any.whl", 18437,
            "98802fee3a11ee76ecaca44429fda8a41bff98b00a0f2838151b113f210cc6fe",
            "41/45/1a4ed80516f02155c51f51e8cedb3c1902296743db0bbc66608a0db2814f"),
        wheel(
            "log_symbols-0.0.14-py3-none-any.whl", 3081, "4952106ff8b605ab7d5081dd2c7e6ca7374584eff7086f499c06edd1ce56dcca",
            "28/5d/d710c38be68b0fb54e645048fe359c3904cc3cb64b2de9d40e1712bf110c"),
        wheel(
            "milc-2.1.0-py3-none-any.whl", 35057, "016fb1349ecccd002e6bbeaf8a204260ccc28992f26e11fd685c8a52cc5f5027",
            "a3/94/cd4c5c4b95e0af45cf224b9f0cb8c65d03f5b1911e09a69f2f4014b91e0d"),
        wheel(
            "pillow-12.3.0-cp312-cp312-macosx_11_0_arm64.whl", 4_780_323,
            "ffd0c5368496f41b0944be820fcb7a838aa6e623d250b01acf2643939c3f99d7",
            "d8/66/9a386a92561f402389a4fc70c18838bf6d35eb5eb5c6850b4b2dc64f5048"),
        wheel(
            "platformdirs-4.13.0-py3-none-any.whl", 32724, "3dbcf4cd708f21cf876c4eaa90e58412bc4f033d87143f41b1493ff77c25b7e1",
            "8d/15/1633010b26e88e872c93b67c0b6c5e174fb74cb6fb5c1472b4d51d4a8f22"),
        wheel(
            "pygments-2.21.0-py3-none-any.whl", 1_250_147, "2363c69b61c4a97c838da3b130dcd6468f4848992b21a82f2a63ec34377137d9",
            "71/46/17f022dd3e953bf20a04a028a21ec746d942f8d2af30fa0f124fa0e6a684"),
        wheel(
            "pyserial-3.5-py2.py3-none-any.whl", 90585, "c4451db6ba391ca6ca299fb3ec7bae67a5c55dde170964c7a14ceefec02f2cf0",
            "07/bc/587a445451b253b285629263eb51c2d8e9bcea4fc97826266d186f96f558"),
        wheel(
            "pyusb-1.3.1-py3-none-any.whl", 58465, "bf9b754557af4717fe80c2b07cc2b923a9151f5c08d17bdb5345dac09d6a0430",
            "28/b8/27e6312e86408a44fe16bd28ee12dd98608b39f7e7e57884a24e8f29b573"),
        wheel(
            "qmk-1.2.0-py2.py3-none-any.whl", 15396, "77fa04a24d36feb7f19f19f190eaf350b78a5caf5ef6a783251902e853fd1809",
            "0b/42/4df974e0378fe66bd2fa8361cce3f3243208a601d49772f7a91d209a2175"),
        wheel(
            "referencing-0.37.0-py3-none-any.whl", 26766, "381329a9f99628c9069361716891d34ad94af76e461dcb0335825aecc7692231",
            "2c/58/ca301544e1fa93ed4f80d724bf5b194f6e4b945841c5bfd555878eea9fcb"),
        wheel(
            "rpds_py-2026.9.1-cp312-cp312-macosx_11_0_arm64.whl", 341_380,
            "e21c1429e205828ea886a2293a4a2c8e01f4c25d9893ca330e97a6cf73f52e7b",
            "90/81/ac6a0d064982251856ce009c9e1dd51a34110b3c055aa7d1aad18b4899a3"),
        wheel(
            "six-1.17.0-py2.py3-none-any.whl", 11050, "4721f391ed90541fddacab5acf947aa0d3dc7d27b2e1e8eda2be8970586c3274",
            "b7/ce/149a00dd41f10bc29e5921b496af8b574d8413afcd5e30dfa0ed46c2cc5e"),
        wheel(
            "spinners-0.0.24-py3-none-any.whl", 5499, "2fa30d0b72c9650ad12bbe031c9943b8d441e41b4f5602b0ec977a19f3290e98",
            "9f/8e/3310207a68118000ca27ac878b8386123628b335ecb3d4bec4743357f0d1"),
        wheel(
            "termcolor-3.3.0-py3-none-any.whl", 7734, "cf642efadaf0a8ebbbf4bc7a31cec2f9b5f21a9f726f4ccbb08192c9c26f43a5",
            "33/d1/8bb87d21e9aeb323cc03034f5eaf2c8f69841e40e4853c2627edf8111ed3"),
        wheel(
            "types_colorama-0.4.15.20260508-py3-none-any.whl", 10755, "b0c39908a3e5171ef1f8bf3d59fae082e9eaff3a19ca49b6d640b83f78cff61c",
            "56/33/a3449e3e93c43861b92d0a93ed4ea5505756463e507625812cfb29c91c7a"),
        wheel(
            "typing_extensions-4.16.0-py3-none-any.whl", 45571, "481caa481374e813c1b176ada14e97f1f67a4539ce9cfeb3f350d78d6370c2e8",
            "49/d3/b8441a820a491ddfc024b0b0cf0393375b75ea13866d9c66727e54c2fc80"),
    ]

    /// The fork and the submodules a Voyager build reads, as GitHub archives at their pinned commits.
    /// shortcut: sizes and hashes are filled in at the first approved download; until then setup refuses to run.
    static let firmware: [Artifact] = [
        archive("zsa/qmk_firmware", firmwareCommit, size: 0, sha256: "", [Unpack(into: "qmk_firmware")]),
        // ChibiOS without other vendors' headers (306 MB of its 368 MB), demos and tests.
        archive(
            "qmk/ChibiOS", chibiosCommit, size: 0, sha256: "",
            [
                Unpack(into: "qmk_firmware/lib/chibios", include: ["*/os/*"], exclude: ["*/os/common/ext/*"]),
                Unpack(
                    into: "qmk_firmware/lib/chibios", include: ["*/os/common/ext/ARM/CMSIS/Core/*", "*/os/common/ext/ST/STM32F3xx/*"]),
            ]),
        // The ChibiOS USB stack borrows LUFA's USB class headers.
        archive("qmk/lufa", lufaCommit, size: 0, sha256: "", [Unpack(into: "qmk_firmware/lib/lufa", include: ["*/LUFA/*"])]),
        archive("qmk/printf", printfCommit, size: 0, sha256: "", [Unpack(into: "qmk_firmware/lib/printf")]),
        archive("zsa/qmk_modules", modulesCommit, size: 0, sha256: "", [Unpack(into: "qmk_firmware/modules/zsa")]),
    ]

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else { preconditionFailure("bad pinned URL \(string)") }
        return url
    }

    private static func wheel(_ name: String, _ size: Int64, _ sha256: String, _ path: String) -> Artifact {
        Artifact(name: name, url: url("https://files.pythonhosted.org/packages/\(path)/\(name)"), size: size, sha256: sha256)
    }

    private static func archive(_ repository: String, _ commit: String, size: Int64, sha256: String, _ unpack: [Unpack]) -> Artifact {
        Artifact(
            name: "\(repository.replacing("/", with: "-"))-\(commit.prefix(7)).tar.gz",
            url: url("https://codeload.github.com/\(repository)/tar.gz/\(commit)"), size: size, sha256: sha256, unpack: unpack)
    }
}
