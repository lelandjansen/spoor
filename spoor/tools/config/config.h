// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#pragma once

#include <string>
#include <string_view>

#include "util/flat_map/flat_map.h"

namespace spoor::tools::config {

enum class OutputFormat {
  kAutomatic,
  kPerfetto,
  kSpoorSymbols,
};

struct Config {
  // Alphabetized to match the order printed in --help.
  std::string output_file;
  OutputFormat output_format;
};

constexpr util::flat_map::FlatMap<std::string_view, OutputFormat, 3>
    kOutputFormats{
        {"automatic", OutputFormat::kAutomatic},
        {"perfetto", OutputFormat::kPerfetto},
        {"spoor_symbols", OutputFormat::kSpoorSymbols},
    };

constexpr std::string_view kOutputFileDoc{"Output file."};
constexpr std::string_view kOutputFileDefaultValue{""};

constexpr std::string_view kOutputFormatDoc{
    "Data output format. Options: %s. \"automatic\" detects the format from "
    "the output file's extension."};
constexpr auto kOutputFormatDefaultValue{OutputFormat::kAutomatic};

auto operator==(const Config& lhs, const Config& rhs) -> bool;

}  // namespace spoor::tools::config