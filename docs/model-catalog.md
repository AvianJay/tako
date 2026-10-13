# Model detection sources

Checked 2026-10-13. The catalog recognizes explicit publisher IDs, vendor-prefixed
IDs, dated snapshots, and standard OpenRouter routing suffixes. Unknown family
members keep manual settings. Detection does not guarantee account access or
that a gateway implements every native model feature.

| Publisher | Added presets | Official source |
| --- | --- | --- |
| OpenAI | GPT Image 2, GPT Image 2.5 Sunburst/Flare, ChatGPT Image Latest; GPT-5.5 | [Image API models](https://developers.openai.com/api/reference/resources/images/methods/generate), [GPT-5.5](https://developers.openai.com/api/docs/models/gpt-5.5) |
| Google | Gemini 2.5 Pro/Flash/Flash-Lite; 3 Flash and 3.1 Pro previews; 3.1/3.5 Flash-Lite; 3.8 Flash; Gemini image models including Nano Banana 2.1 | [Model directory](https://ai.google.dev/gemini-api/docs/models), [2.5 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash), [2.5 image](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-image), [3.1 image](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image), [Nano Banana 2.1](https://ai.google.dev/gemini-api/docs/models/gemini-nano-banana-2.1), [image Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite-image) |
| Alibaba | Qwen 3.5 Plus/Flash, 3.6 Plus, 3.8 Max | [3.5 Plus](https://www.alibabacloud.com/help/en/model-studio/qwen3-5-plus), [3.5 Flash](https://www.alibabacloud.com/help/en/model-studio/qwen3-5-flash), [3.6 Plus](https://www.alibabacloud.com/help/en/model-studio/qwen3-6-plus), [3.8 Max](https://help.aliyun.com/en/model-studio/qwen3-8-max) |
| xAI | Grok 4.7; Grok Imagine Image 2.0 | [Grok 4.7](https://docs.x.ai/developers/models/grok-4.7), [image model](https://docs.x.ai/developers/models/grok-imagine-image-2.0), [edits](https://docs.x.ai/developers/model-capabilities/images/editing), [multiple references](https://docs.x.ai/developers/model-capabilities/images/multi-image-editing) |
| Mistral | Large 4, Medium 3.5, Small 4 | [Large 4](https://docs.mistral.ai/models/mistral-large-4-0), [Medium 3.5](https://docs.mistral.ai/models/mistral-medium-3-5-26-04), [Small 4](https://docs.mistral.ai/models/mistral-small-4-0-26-03), [reasoning](https://docs.mistral.ai/studio/conversations/reasoning) |
| Cohere | Command A+, A, A Reasoning, A Vision, R/R+/R7B dated variants | [Model limits and modalities](https://docs.cohere.com/v2/docs/models) |

Grok and Mistral chat entries use an 8,192-token output default because their
referenced model pages publish context windows without a separate output cap.
This is an app default, not a claimed provider maximum. Image API entries keep
the existing token fields as editor fallbacks; those APIs do not use chat token
budgets.

Gemini image presets select chat image output for compatible gateways such as
OpenRouter. Google's native `generateContent` image API is not the OpenAI chat
protocol; a native Google image endpoint needs a gateway. Google's text models
can use its [OpenAI-compatible chat endpoint](https://ai.google.dev/gemini-api/docs/openai).
Cohere presets likewise describe capabilities for compatible deployments;
they do not add Cohere's native Chat API protocol.
Command A Vision has image input but [does not support tool use](https://docs.cohere.com/v2/docs/command-a-vision).

For `api.x.ai`, image edits use JSON image data URIs and accept up to five
references. Other Images API endpoints retain their multipart edit format.
