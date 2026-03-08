// Read the version from the command line

const version = process.argv[2]
if (!version) {
    console.error("Usage: node bump_version.js <version>")
    process.exit(1)
}


const gen_config = (version, branch = "release/9.0") => (`{
    "name:": "KiCad Huaqiu",
    "output_prefix": "kicad-huaqiu-",
    "package_version": "${version}",
    "train": "stable",
    "build_mode": "Release",
    "nsis": {
        "file": "install.nsi"
    },
    "sources": {
        "kicad": {
            "ref": "branch/${branch}"
        },
        "symbols": {
            "ref": "tag/${version}"
        },
        "footprints": {
            "ref": "tag/${version}"
        },
        "3dmodels": {
            "ref": "tag/${version}"
        },
        "templates": {
            "ref": "tag/${version}"
        },
        "hqpcb": {
            "ref": "KiCAD-HQPCB-2.0.8"
        },
        "hqpcb-sha256": {
            "ref": "bfc60abb24835c1177dd73cd09e05fcea5bb1984805dc053b7a61822ec8b8ff0"
        },
        "hqdfm": {
            "ref": "KICAD-HQDFM-2.0.4"
        },
        "hqdfm-sha256": {
            "ref": "a318166f6e319b73d51465407595620544e8805ca5bd40ddb549ca839a018877"
        },
        "search": {
            "ref": "KiCAD-HQSearch-1.0.2"
        },
        "search-sha256": {
            "ref": "2b660bf97fafdf25f32a89c3c3d664cc615559fb994a03fbfa146966b5799e45"
        }
    },
    "vcpkg": {
        "manifest_mode": true
    }
}`)

const config = gen_config(version)


writeFileSync("build-configs/kicad-hq.json", config)

const { execSync } = require("child_process")
execSync("git add build-configs/kicad-hq.json")
execSync(`git commit -m "Bump version to ${version}"`)
execSync(`git tag -a ${version} -m "Version ${version}"`)
execSync(`git push origin ${version}`)
