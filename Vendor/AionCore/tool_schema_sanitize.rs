//! Reference MCP tool schema sanitizer for AionCore (Citadel vendor patch).
//! Port of OpenCode `sanitizeOpenAISchema` — apply before cloud provider tool serialization.

use serde_json::{Map, Value};

const ALLOWED_TYPES: &[&str] = &[
    "string", "number", "boolean", "integer", "object", "array", "null",
];

pub enum ProviderToolProfile {
    OpenAiCompatible,
    Anthropic,
    Gemini,
    LocalPermissive,
}

pub fn profile_for_platform(platform: &str) -> ProviderToolProfile {
    match platform.to_lowercase().as_str() {
        "anthropic" => ProviderToolProfile::Anthropic,
        "gemini" | "google" => ProviderToolProfile::Gemini,
        "ollama" => ProviderToolProfile::LocalPermissive,
        _ => ProviderToolProfile::OpenAiCompatible,
    }
}

pub fn sanitize_for_provider(value: &Value, profile: ProviderToolProfile) -> Value {
    match profile {
        ProviderToolProfile::LocalPermissive => value.clone(),
        ProviderToolProfile::OpenAiCompatible | ProviderToolProfile::Anthropic => {
            sanitize_openai(value).unwrap_or_else(|| json_empty_object())
        }
        ProviderToolProfile::Gemini => sanitize_gemini(value),
    }
}

fn sanitize_gemini(value: &Value) -> Value {
    let openai = sanitize_openai(value).unwrap_or_else(|| json_empty_object());
    sanitize_gemini_from_openai(openai)
}

fn sanitize_openai(value: &Value) -> Option<Value> {
    match value {
        Value::Bool(true) => Some(json!({"type": "string"})),
        Value::Bool(false) => Some(json!({"type": "string"})),
        Value::Array(items) => Some(Value::Array(
            items.iter().filter_map(sanitize_openai).collect(),
        )),
        Value::Object(map) => sanitize_openai_object(map),
        _ => Some(value.clone()),
    }
}

fn sanitize_openai_object(map: &Map<String, Value>) -> Option<Value> {
    let mut result = Map::new();

    if let Some(Value::String(reference)) = map.get("$ref") {
        result.insert("$ref".into(), Value::String(reference.clone()));
    }
    if let Some(Value::String(desc)) = map.get("description") {
        result.insert("description".into(), Value::String(desc.clone()));
    }
    if let Some(const_value) = map.get("const") {
        result.insert("enum".into(), Value::Array(vec![const_value.clone()]));
    } else if let Some(Value::Array(enum_values)) = map.get("enum") {
        result.insert("enum".into(), Value::Array(enum_values.clone()));
    }

    if let Some(Value::Object(properties)) = map.get("properties") {
        let mut sanitized = Map::new();
        for (key, item) in properties {
            if let Some(value) = sanitize_openai(item) {
                sanitized.insert(key.clone(), value);
            }
        }
        result.insert("properties".into(), Value::Object(sanitized));
    }

    if let Some(Value::Array(required)) = map.get("required") {
        let names: Vec<Value> = required
            .iter()
            .filter_map(|v| v.as_str().map(|s| Value::String(s.to_string())))
            .collect();
        if !names.is_empty() {
            result.insert("required".into(), Value::Array(names));
        }
    }

    if let Some(items) = map.get("items") {
        if let Some(sanitized) = sanitize_openai(items) {
            result.insert("items".into(), sanitized);
        }
    }

    if let Some(additional) = map.get("additionalProperties") {
        match additional {
            Value::Bool(flag) => {
                result.insert("additionalProperties".into(), Value::Bool(*flag));
            }
            other => {
                if let Some(sanitized) = sanitize_openai(other) {
                    result.insert("additionalProperties".into(), sanitized);
                }
            }
        }
    }

    for key in ["anyOf", "oneOf", "allOf"] {
        if let Some(Value::Array(branch)) = map.get(key) {
            let sanitized: Vec<Value> = branch.iter().filter_map(sanitize_openai).collect();
            if !sanitized.is_empty() {
                result.insert(key.into(), Value::Array(sanitized));
            }
        }
    }

    let schema_types = normalized_types(map.get("type"));
    let inferred = if !schema_types.is_empty() {
        schema_types
    } else if ["properties", "required", "additionalProperties"]
        .iter()
        .any(|k| map.contains_key(*k))
    {
        vec!["object".to_string()]
    } else if map.contains_key("items") || map.contains_key("prefixItems") {
        vec!["array".to_string()]
    } else if result.contains_key("enum") || map.contains_key("format") {
        vec!["string".to_string()]
    } else if [
        "minimum",
        "maximum",
        "exclusiveMinimum",
        "exclusiveMaximum",
        "multipleOf",
    ]
    .iter()
    .any(|k| map.contains_key(*k))
    {
        vec!["number".to_string()]
    } else if map.contains_key("description") {
        vec!["string".to_string()]
    } else {
        vec![]
    };

    finalize_openai_object(result, inferred)
}

fn finalize_openai_object(mut result: Map<String, Value>, inferred: Vec<String>) -> Option<Value> {
    if inferred.is_empty() {
        return None;
    }
    result.insert(
        "type".into(),
        if inferred.len() == 1 {
            Value::String(inferred[0].clone())
        } else {
            Value::Array(inferred.iter().cloned().map(Value::String).collect())
        },
    );
    if inferred.iter().any(|t| t == "object") && !result.contains_key("properties") {
        result.insert("properties".into(), Value::Object(Map::new()));
    }
    if inferred.iter().any(|t| t == "object") && !result.contains_key("additionalProperties") {
        result.insert("additionalProperties".into(), Value::Bool(false));
    }
    if inferred.iter().any(|t| t == "array") && !result.contains_key("items") {
        result.insert("items".into(), json!({"type": "string"}));
    }
    Some(Value::Object(result))
}

fn normalized_types(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::String(t)) if ALLOWED_TYPES.contains(&t.as_str()) => vec![t.clone()],
        Some(Value::Array(types)) => types
            .iter()
            .filter_map(|v| v.as_str())
            .filter(|t| ALLOWED_TYPES.contains(t))
            .map(|s| s.to_string())
            .collect(),
        _ => vec![],
    }
}

fn sanitize_gemini_from_openai(value: Value) -> Value {
    let Value::Object(mut object) = value else {
        return value;
    };
    if let Some(Value::Array(types)) = object.get("type") {
        if types.len() > 1 {
            let non_null: Vec<&str> = types
                .iter()
                .filter_map(|v| v.as_str())
                .filter(|t| *t != "null")
                .collect();
            if non_null.len() == 1 {
                object.insert("type".into(), Value::String(non_null[0].to_string()));
            } else if non_null.len() > 1 {
                object.remove("type");
                object.insert(
                    "anyOf".into(),
                    Value::Array(
                        non_null
                            .into_iter()
                            .map(|t| json!({"type": t}))
                            .collect(),
                    ),
                );
            }
        }
    }
    Value::Object(object)
}

fn json_empty_object() -> Value {
    Value::Object(Map::new())
}

macro_rules! json {
    ($($json:tt)+) => {
        serde_json::json!($($json)+)
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn drops_unsupported_keywords_via_rebuild() {
        let input = json!({
            "type": "object",
            "properties": {
                "path": { "type": "string", "pattern": "^/.+" }
            },
            "pattern": "ignored",
            "additionalProperties": true
        });
        let out = sanitize_for_provider(&input, ProviderToolProfile::OpenAiCompatible);
        assert!(out.get("pattern").is_none());
        assert_eq!(out["additionalProperties"], json!(false));
    }
}
