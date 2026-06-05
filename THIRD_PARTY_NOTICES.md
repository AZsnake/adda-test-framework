# Third-Party Notices

## Verilog — INNOFIDEI legacy control path

The following files retain a historical header referencing INNOFIDEI
Technologies (circa 2007–2012):

- `rf_ctrl_path/rf_ctrl_path.v`
- `rf_ctrl_path/rf_ctrl_reg.v`
- `rf_ctrl_path/rf_cmd_arb.v`
- `rf_ctrl_path/rf_spram_mux.v`
- `rf_ctrl_path/spi_cmd_state.v`
- `rf_ctrl_path/gpo_cmd_state.v`
- `rf_ctrl_path/spi_core/*.v`

If you redistribute this repository, verify that you have the right to
include these modules or replace them with a clean-room implementation.

## Chip datasheets (`docs/specs/`)

PDF files under `docs/specs/` are copyrighted by their respective vendors
(Analog Devices, Skyworks / Silicon Labs, etc.). Prefer downloading current
revisions from the vendor website instead of redistributing PDFs in forks.

## Vendor tools

ClockBuilder Pro exports used to generate SI5340 init tables are subject to
Silicon Labs tool and device license terms.
