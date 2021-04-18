// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#pragma once

#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

#include "absl/flags/declare.h"
#include "absl/flags/parse.h"
#include "absl/strings/string_view.h"
#include "spoor/instrumentation/config/config.h"
#include "util/env/env.h"
#include "util/flags/optional.h"
#include "util/numeric.h"

ABSL_DECLARE_FLAG(bool, enable_runtime);       // NOLINT
ABSL_DECLARE_FLAG(bool, force_binary_output);  // NOLINT
ABSL_DECLARE_FLAG(                             // NOLINT
    util::flags::Optional<std::string>, function_allow_list_file);
ABSL_DECLARE_FLAG(  // NOLINT
    util::flags::Optional<std::string>, function_blocklist_file);
ABSL_DECLARE_FLAG(bool, initialize_runtime);                       // NOLINT
ABSL_DECLARE_FLAG(bool, inject_instrumentation);                   // NOLINT
ABSL_DECLARE_FLAG(std::string, instrumentation_map_output_path);   // NOLINT
ABSL_DECLARE_FLAG(uint32, min_instruction_threshold);              // NOLINT
ABSL_DECLARE_FLAG(util::flags::Optional<std::string>, module_id);  // NOLINT
ABSL_DECLARE_FLAG(std::string, output_file);                       // NOLINT
ABSL_DECLARE_FLAG(                                                 // NOLINT
    spoor::instrumentation::config::OutputLanguage, output_language);

namespace spoor::instrumentation::config {
auto ConfigFromCommandLineOrEnv(int argc, char** argv,
                                const util::env::GetEnv& get_env = std::getenv)
    -> std::pair<Config, std::vector<char*>>;

auto AbslParseFlag(absl::string_view user_key, OutputLanguage* language,
                   std::string* error) -> bool;
auto AbslUnparseFlag(OutputLanguage language) -> std::string;

}  // namespace spoor::instrumentation::config