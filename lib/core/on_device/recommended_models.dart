/// One file of a recommended model, pinned to a Hugging Face commit and
/// checked against its SHA-256 after download.
class RecommendedFile {
  const RecommendedFile(
    this.repo,
    this.revision,
    this.file,
    this.size,
    this.sha256,
  );
  final String repo;
  final String revision;
  final String file;
  final int size;
  final String sha256;
  Uri get url => Uri.https('huggingface.co', '/$repo/resolve/$revision/$file');
}

enum RecommendedUse { fast, balanced, best, vision }

/// Models known to chat and call tools well with llama.cpp on a phone. All
/// are plain transformers: llama.cpp reuses the cached start of the prompt on
/// every tool round, which hybrid models such as Qwen3.5 cannot.
/// Checked on 2026-10-12; all are Apache-2.0.
class RecommendedModel {
  const RecommendedModel({
    required this.id,
    required this.name,
    required this.use,
    required this.memoryGb,
    required this.model,
    this.projector,
  });
  final String id;
  final String name;
  final RecommendedUse use;

  /// Phone memory the model needs to run comfortably.
  final int memoryGb;
  final RecommendedFile model;

  /// The vision projector, downloaded only when asked for.
  final RecommendedFile? projector;

  /// The name the projector is saved as; several repos share `mmproj-F16`.
  String get projectorName =>
      '${model.file.substring(0, model.file.length - 5)}.mmproj.gguf';

  static const all = [
    RecommendedModel(
      id: 'qwen3-0.6b',
      name: 'Qwen3 0.6B',
      use: RecommendedUse.fast,
      memoryGb: 3,
      model: RecommendedFile(
        'Qwen/Qwen3-0.6B-GGUF',
        '23749fefcc72300e3a2ad315e1317431b06b590a',
        'Qwen3-0.6B-Q8_0.gguf',
        639446688,
        '9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031',
      ),
    ),
    RecommendedModel(
      id: 'qwen3-1.7b',
      name: 'Qwen3 1.7B',
      use: RecommendedUse.balanced,
      memoryGb: 4,
      model: RecommendedFile(
        'unsloth/Qwen3-1.7B-GGUF',
        'd7f544eead698dbd1f15126ef60b45a1e1933222',
        'Qwen3-1.7B-Q4_K_M.gguf',
        1107409472,
        'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897',
      ),
    ),
    RecommendedModel(
      id: 'qwen3-4b-instruct-2507',
      name: 'Qwen3 4B Instruct 2507',
      use: RecommendedUse.best,
      memoryGb: 8,
      model: RecommendedFile(
        'unsloth/Qwen3-4B-Instruct-2507-GGUF',
        'a06e946bb6b655725eafa393f4a9745d460374c9',
        'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
        2497281120,
        '3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597',
      ),
    ),
    RecommendedModel(
      id: 'qwen3-vl-2b-instruct',
      name: 'Qwen3-VL 2B Instruct',
      use: RecommendedUse.vision,
      memoryGb: 6,
      model: RecommendedFile(
        'Qwen/Qwen3-VL-2B-Instruct-GGUF',
        '52d6c8ffea26cc873ac5ad116f8631268d7eb503',
        'Qwen3VL-2B-Instruct-Q4_K_M.gguf',
        1107409952,
        '089d75c52f4b7ffc56ba998ffc50aae89fcafc755f9e7208aacca281dca6c2ae',
      ),
      projector: RecommendedFile(
        'Qwen/Qwen3-VL-2B-Instruct-GGUF',
        '52d6c8ffea26cc873ac5ad116f8631268d7eb503',
        'mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf',
        445053216,
        'f9a68fabba69c3b81e153367b2c7521030b0fa8bb0de400c9599c8e6725f9c82',
      ),
    ),
  ];
}
