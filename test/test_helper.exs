alias Harald.Transport.{UARTBehaviour, UARTBehaviourMock}

Mox.defmock(UARTBehaviourMock, for: UARTBehaviour)
ExUnit.start()
:ok = Application.ensure_started(:stream_data)
