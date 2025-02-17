# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from amaranth import unsigned, Signal
from amaranth.hdl.ast import Mux
from amaranth.hdl.dsl import Module
from amaranth_cfu import InstructionBase, SimpleElaboratable, ValueBuffer
from .constants import Constants
from ..stream import Endpoint, connect


class StatusRegister(SimpleElaboratable):
    """A register set by gateware.

    Allows gateware to provide data to a CPU.

    Parameters
    ----------

    valid_at_reset: bool
      Whether payload is valid at reset or register ought to wait
      to transfer a value from its input stream.

    ready_when_valid: bool
      Whether the register should allow overwriting valid values
      with new values from its input stream.
      If true, the register is unconditionally ready to accept new values.
      If false, the register will only accept new values when it is not
      already holding a valid value.

    Attributes
    ----------

    input: Endpoint(unsigned(32)), in
      A stream of new values.

    invalidate: Signal(), in
      Causes valid to be deassserted.

    value: Signal(32), out
      The value held by the register. Received from sink.payload.

    valid: Signal(), out
      Deasserted when clear is asserted. Asserted when new value
      received at sink.

    """

    def __init__(self, valid_at_reset=True, ready_when_valid=True):
        super().__init__()
        self.ready_when_valid = ready_when_valid
        self.input = Endpoint(unsigned(32))
        self.invalidate = Signal()
        self.valid = Signal(reset=valid_at_reset)
        self.value = Signal(32)

    def elab(self, m):
        if self.ready_when_valid:
            m.d.comb += self.input.ready.eq(1)
        else:
            m.d.comb += self.input.ready.eq(~self.valid)
        with m.If(self.invalidate):
            m.d.sync += self.valid.eq(0)
        with m.If(self.input.is_transferring()):
            m.d.sync += self.value.eq(self.input.payload)
            m.d.sync += self.valid.eq(1)


class GetInstruction(InstructionBase):
    """An instruction used by CPU to get values from the CFU.

    Returns current value of each register

    Attributes
    ----------

    input_streams: dict[id, Endpoint[unsigned(32)]], in
      Input value streams for each register.

    read_strobes: dict[id, Signal(1)], out
      Asserted for one cycle when the corresponding register id is read.
    """

    # The list of all register IDs that may be fetched
    REGISTER_IDS = [
        Constants.REG_MACC_OUT,
        Constants.REG_OUTPUT_WORD,
        Constants.REG_VERIFY,
    ]

    VALID_AT_RESET = {
        Constants.REG_VERIFY,
    }

    # Registers which the CPU must read every value from exactly once:
    # The register won't accept new values from its input stream until the
    # existing value has been read out.
    # The CPU will block until a value has been received from the input stream.
    READ_EXACTLY_ONCE = {
        Constants.REG_MACC_OUT,
        Constants.REG_OUTPUT_WORD,
    }

    def __init__(self):
        super().__init__()
        self.input_streams = {}
        self.invalidates = {}
        self.read_strobes = {}
        for i in self.REGISTER_IDS:
            self.input_streams[i] = Endpoint(unsigned(32), name=f"sink_{i:02x}")
            self.invalidates[i] = Signal(name=f"clear_{i:02x}")
            self.read_strobes[i] = Signal(name=f"read_strobe_{i:02x}")

    def read_reg(self, m, registers, register_num,
                 continue_state, finish_state):
        with m.Switch(register_num):
            for i in self.REGISTER_IDS:
                with m.Case(i):
                    with m.If(registers[i].valid):
                        # Get value and finish only if register value is valid
                        m.d.sync += self.output.eq(registers[i].value)
                        m.d.sync += self.read_strobes[i].eq(1)
                        m.d.sync += self.done.eq(1)
                        m.next = finish_state
                    with m.Else():
                        m.next = continue_state
            with m.Default():
                m.d.sync += self.output.eq(0)
                m.d.sync += self.done.eq(1)
                m.next = finish_state

    def elab(self, m: Module):
        # Make registers and plumb sinks and read_strobes through
        registers = {i: StatusRegister(valid_at_reset=(i in self.VALID_AT_RESET),
                                       ready_when_valid=(i not in self.READ_EXACTLY_ONCE))
                     for i in self.REGISTER_IDS}
        for i, register in registers.items():
            m.submodules[f"reg_{i:02x}"] = register
            m.d.comb += connect(self.input_streams[i], register.input)
            if i in self.READ_EXACTLY_ONCE:
                # Reading from it invalidates the value, in preparation for
                # receiving the next one.
                m.d.comb += register.invalidate.eq(self.read_strobes[i] |
                                                   self.invalidates[i])
            else:
                m.d.comb += register.invalidate.eq(self.invalidates[i])
            m.d.sync += self.read_strobes[i].eq(0)  # strobes off by default

        # Handle CFU start
        f7_buf = Signal(7)
        with m.FSM():
            with m.State("WAIT_START"):
                with m.If(self.start):
                    m.d.sync += f7_buf.eq(self.funct7)
                    self.read_reg(m, registers, self.funct7, "GETTING", "DONE")
            with m.State("GETTING"):
                self.read_reg(m, registers, f7_buf, "GETTING", "DONE")
            with m.State("DONE"):
                m.d.sync += self.done.eq(0)
                m.next = "WAIT_START"
