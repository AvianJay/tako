// Protocol snapshots with synthetic, non-secret identifiers. Each fixture is fed
// to adapters as one-byte network chunks to exercise UTF-8 and SSE boundaries.
const chatCompletionsStream = r'''
: keep-alive

data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"<thi"},"finish_reason":null}]}

data: {"choices":[{"index":0,"delta":{"content":"nk>想一想</th"},"finish_reason":null}]}

data: {"choices":[{"index":0,"delta":{"content":"ink>你好🌊","tool_calls":[{"index":0,"id":"call_a","function":{"name":"weather","arguments":""}},{"index":1,"id":"call_b","function":{"name":"clock","arguments":""}}]},"finish_reason":null}]}

data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\"city\":\"台北\"}"}},{"index":0,"function":{"arguments":"{\"city\":"}}]},"finish_reason":null}]}

data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"東京\"}"}}]},"finish_reason":"tool_calls"}]}

data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}

data: [DONE]

''';

const responsesStream = r'''
event: response.created
data: {"type":"response.created","response":{"id":"resp_1"}}

event: response.reasoning_summary_text.delta
data: {"type":"response.reasoning_summary_text.delta","output_index":0,"delta":"想一想"}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_1","type":"reasoning","encrypted_content":"opaque-reasoning","summary":[{"type":"summary_text","text":"想一想"}]}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"你好🌊"}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":2,"item":{"id":"fc_a","call_id":"call_a","type":"function_call","name":"weather","arguments":""}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":3,"item":{"id":"fc_b","call_id":"call_b","type":"function_call","name":"clock","arguments":""}}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","item_id":"fc_b","delta":"{\"city\":\"台北\"}"}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","item_id":"fc_a","delta":"{\"city\":"}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","item_id":"fc_a","delta":"\"東京\"}"}

event: response.function_call_arguments.done
data: {"type":"response.function_call_arguments.done","item_id":"fc_a","arguments":"{\"city\":\"東京\"}"}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":2,"item":{"id":"fc_a","call_id":"call_a","type":"function_call","name":"weather","arguments":"{\"city\":\"東京\"}"}}

event: response.output_item.done
data: {"type":"response.output_item.done","output_index":3,"item":{"id":"fc_b","call_id":"call_b","type":"function_call","name":"clock","arguments":"{\"city\":\"台北\"}"}}

event: response.completed
data: {"type":"response.completed","response":{"usage":{"input_tokens":12,"output_tokens":8,"total_tokens":20}}}

''';

const messagesStream = r'''
event: message_start
data: {"type":"message_start","message":{"usage":{"input_tokens":12,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"想一想"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"signed-"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"thinking"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"你好🌊"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"call_a","name":"weather","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"city\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"東京\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":2}

event: content_block_start
data: {"type":"content_block_start","index":3,"content_block":{"type":"tool_use","id":"call_b","name":"clock","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":3,"delta":{"type":"input_json_delta","partial_json":"{\"city\":\"台北\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":3}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":8}}

event: message_stop
data: {"type":"message_stop"}

''';

const chatErrorStream = r'''
data: {"choices":[{"delta":{"content":"partial"},"index":0}]}

data: {"error":{"message":"overloaded","type":"server_error"}}

''';

const responsesErrorStream = r'''
event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"partial"}

event: response.failed
data: {"type":"response.failed","response":{"error":{"message":"overloaded","code":"server_error"}}}

''';

const messagesErrorStream = r'''
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}

event: error
data: {"type":"error","error":{"message":"overloaded","type":"overloaded_error"}}

''';
