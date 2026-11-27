//! Narrow, fail-closed verifier for the native AttoLang proxy flags-2-env TOML contract.
//! Intentionally accepts only the reviewed TOML subset (simple strings and a string array).
use std::{collections::BTreeMap, env, fs, path::Path};

fn quoted(value: &str) -> Result<&str, String> {
    let raw = value.trim();
    let body = raw.strip_prefix('"').and_then(|x| x.strip_suffix('"'))
        .ok_or_else(|| "expected simple TOML double-quoted string".to_string())?;
    if body.contains('"') || body.contains('\\') || body.chars().any(char::is_control) {
        return Err("escaped, multiline or embedded-quote strings are not approved".into());
    }
    Ok(body)
}

fn aliases(value: &str) -> Result<Vec<&str>, String> {
    let text = value.trim().strip_prefix('[')
        .and_then(|s| s.strip_suffix(']'))
        .ok_or_else(|| "aliases must be an inline string array".to_string())?;
    text.split(',').map(quoted).collect()
}

fn validate(text: &str) -> Result<(), String> {
    if text.len() > 8192 { return Err("oversized CLI configuration".into()); }
    let mut section = false;
    let mut fields = BTreeMap::<&str, &str>::new();
    for (n, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        if line.starts_with('[') {
            if section || line != "[flags.config-yaml]" {
                return Err(format!("unexpected/duplicate TOML table at line {}", n+1));
            }
            section = true;
            continue;
        }
        if !section { return Err(format!("property outside expected table: {}", n+1)); }
        let (key, val) = line.split_once('=')
            .ok_or_else(|| format!("malformed assignment at line {}", n+1))?;
        let key = key.trim();
        if !matches!(key, "env" | "type" | "aliases" | "help") {
            return Err(format!("unexpected key {key}"));
        }
        if fields.insert(key, val.trim()).is_some() {
            return Err(format!("duplicate TOML key {key}"));
        }
    }
    if !section || fields.len() != 4 {
        return Err("required flags.config-yaml fields are absent".into());
    }
    if quoted(fields["env"])? != "ores_proxy_conf_yaml" ||
        quoted(fields["type"])? != "string" {
        return Err("flags-2-env mapping or value type changed".into());
    }
    if aliases(fields["aliases"])? != ["config-yaml", "conf"] {
        return Err("unexpected flag aliases or ordering".into());
    }
    if quoted(fields["help"])?.is_empty() {
        return Err("help must be a nonempty simple string".into());
    }
    Ok(())
}

fn verify_file(path: &Path) -> Result<(), String> {
    let meta = fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if !meta.file_type().is_file() || meta.len() > 8192 {
        return Err("CLI configuration must be a bounded ordinary file, not a symlink".into());
    }
    let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
    validate(&text)
}

fn main() {
    let mut args = env::args_os().skip(1);
    let Some(path) = args.next() else {
        eprintln!("Usage: flags_contract .cli-flags.toml");
        std::process::exit(2);
    };
    if args.next().is_some() {
        eprintln!("exactly one path is required");
        std::process::exit(2);
    }
    if let Err(error) = verify_file(Path::new(&path)) {
        eprintln!("FLAGS_2_ENV_CONTRACT_FAIL: {error}");
        std::process::exit(1);
    }
    println!("FLAGS_2_ENV_CONTRACT_PASS (host-only; AttoLang guest NOT_EXECUTED)");
}

#[cfg(test)]
mod tests {
    use super::*;
    const GOOD: &str = "# policy\n[flags.config-yaml]\nenv = \"ores_proxy_conf_yaml\"\naliases = [\"config-yaml\", \"conf\"]\ntype = \"string\"\nhelp = \"Absolute trusted path.\"\n";
    #[test]
    fn canonical_contract_passes() { assert!(validate(GOOD).is_ok()); }
    #[test]
    fn mappings_cannot_be_replaced_or_reordered() {
        for bad in [
            GOOD.replace("ores_proxy_conf_yaml", "OTHER"),
            GOOD.replace("\"string\"", "\"boolean\""),
            GOOD.replace("[\"config-yaml\", \"conf\"]", "[\"conf\", \"config-yaml\"]"),
            GOOD.replace("flags.config-yaml", "flags.config-yaml.extra"),
            GOOD.replace("help =", "comment ="),
        ] { assert!(validate(&bad).is_err(), "{bad}"); }
    }
    #[test]
    fn rejects_duplicates_unknown_fields_and_extra_tables() {
        for suffix in [
            "env = \"ores_proxy_conf_yaml\"\n",
            "unsafe = \"yes\"\n",
            "[flags.other]\nenv = \"no\"\n",
            "[flags.config-yaml]\n",
        ] { assert!(validate(&(GOOD.to_owned() + suffix)).is_err()); }
        assert!(validate(&GOOD.replace("[flags.config-yaml]", "")).is_err());
    }
    #[test]
    fn refuses_ambiguous_toml_not_in_reviewed_subset() {
        for bad in [
            GOOD.replace("\"string\"", "'string'"),
            GOOD.replace("\"string\"", "\"str\\u0069ng\""),
            GOOD.replace("\"conf\"]", "\"conf\",]"),
            GOOD.replace("env = ", "env = \"other\" #\nenv = "),
            GOOD.replace("type = ", "type = \"string\" # trick\n"),
        ] { assert!(validate(&bad).is_err(), "{bad}"); }
    }
    #[cfg(unix)]
    #[test]
    fn rejects_symlink_to_valid_toml() {
        use std::os::unix::fs::symlink;
        let temp = std::env::temp_dir().join(format!("atto-flags-{}-{}", std::process::id(), "test"));
        let original = temp.with_extension("toml");
        let _ = fs::remove_file(&temp);
        fs::write(&original, GOOD).unwrap();
        symlink(&original, &temp).unwrap();
        assert!(verify_file(&temp).is_err());
        fs::remove_file(&temp).unwrap();
        fs::remove_file(&original).unwrap();
    }
}
