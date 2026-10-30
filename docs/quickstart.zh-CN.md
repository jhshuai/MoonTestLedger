# 中文上手与工作流

MoonTestLedger 面向收集分片、多环境和重试 JUnit 报告的 CI 维护者。它核对**外部声明的完整预期清单**、保留每次尝试及原始 XML，并在报告缺失时返回“不完整”。它不执行测试、不自动缩小清单，也不将一次恢复解释为统计意义上的 flaky 结论。独立贡献与相邻 MoonBit API 见[生态调研](ecosystem-review.md)，第三方来源见[许可证记录](../THIRD_PARTY.md)。

## 一条命令完成三个真实工作流

从仓库根目录，使用 README 记录的工具链执行：

```sh
moon update
moon run scripts/workflow-demo.mbtx wasm
```

脚本创建独立临时目录，打印其完整路径并保留证据、HTML、每条实际命令的 stdout/stderr/退出状态及 `results.json`。也可指定**尚不存在且父目录已存在**的目录：`moon run scripts/workflow-demo.mbtx wasm NEW-DIRECTORY`。已有目录被拒绝。用 `native` 替换 `wasm` 可实际运行原生 CLI，需要本机 C 编译器/SDK。无需 GitHub 账号、私有服务、Python 或 Java。

| 使用场景 | 实际流程和预期结果 | 保留的证据 |
| --- | --- | --- |
| PR 分片测试失败，交付给另一位开发者离线排查 | 读取未改动的上游 Jest XML → 保存归档 → 创建完整交付 → 离线验证；门禁 **1**，完整六个用例 | 全清单、原始 XML、摘要、HTML、完整性清单、ZIP 和完成回执 |
| CI 工件没有下载成功，防止漏测变绿 | 使用同一个完整六用例清单和缺失报告 bundle；门禁 **3**，不能靠删除预期用例通过 | 缺失的 `jest-main` 以及全部六个预期用例仍在 |
| 支付用例失败后选择性重试成功 | 读取两个尝试的 XML → 按声明顺序对账；门禁 **0**，收紧恢复策略时门禁 **1** | 三个用例、两个报告、恢复用例的两次观察及失败载荷 |

Jest 数据来自 dorny/test-reporter，MIT，固定来源和哈希见[样例来源](../examples/README.md)。支付重试是明确标注的项目自建场景，Apache-2.0；不冒充真实生产运行。真实 pytest、Surefire、Gradle 捕获另见[生产者兼容性](../examples/producers/README.md)。

每个场景额外实际验证：拒绝覆盖已有归档并保持字节不变；修改 HTML 后离线验证返回 **2**；恢复原始字节后恢复原门禁。演示脚本本身在所有断言通过时退出 0，其中的预期门禁 1/3 不会被改成产品成功状态。失败立即停止并保留已有记录；未产生 `results.json` 就不能认为该演示完整通过。

## 功能与证据对照

以下入口帮助使用者选择对应的 API、命令和可运行样例。

| 已实现能力 | 公共入口 / 工作流 | 检查与样例 |
| --- | --- | --- |
| 完整清单、精确身份、重试顺序、原子接收 | `RunPlan`、`Ledger`、`parse_junit` | `ledger/*test.mbt`、`junit/*test.mbt`；上述三个场景 |
| 可重放证据和保守门禁 | `Evidence`、`archive`、`verify` | `wire/evidence_test.mbt`；相同 XML / 全清单保持 |
| 完整交付、离线重验和历史版本 | `ci-report`、`verify-delivery` | `scripts/delivery-e2e.mbtx`、`scripts/check-golden-delivery.mbtx`；[真实 GitHub 传输记录](delivery-validation.md) |
| 未来清单变更审阅，拒绝陈旧批准 | `PlanReview`、`review-plan`、`apply-plan-review` | `wire/plan_review_test.mbt`、`scripts/review-e2e.mbtx` |
| 下游独立采用 | 公共 facade、独立 workspace 消费者 | `moon run scripts/check-consumer.mbtx TARGET`；[消费者说明](../examples/consumer/README.md) |
| 原生交付 | `--version`、有校验和的 GitHub 预览发行版 | [发行流程](releases.md)、实际按平台执行的清单 |

完整标准检查：`moon run scripts/verify.mbtx TARGET`，分别使用 `wasm`、`wasm-gc`、`js`、`native`；包含格式、接口漂移、严格检查/构建/测试及适用工作流。文件 CLI 仅支持 Wasm/native；Wasm I/O 依赖 moonrun 宿主，不宣称浏览器/WASI 文件 CLI 支持。CI 的已执行结果与配置分开记录。

2026-10-30 本地实测：固定工具链下，Windows/Wasm 完整验证器通过（123 项测试、接口/格式/严格检查及全部适用工作流）；新的一键演示分别实际运行于 Windows/Wasm 与 Linux/native，三个门禁、完整清单、原始 XML、覆盖拒绝及篡改后恢复均通过。该记录不声称已执行之后提交的远端 CI；远端结果以具体提交的 Actions 运行为准。

## 使用边界

- 历史原生段错误仍未定位；[诊断说明](native-diagnostics.md)保留风险、捕获方法及检查局限。后续通过的运行不能当作根因修复。
- 模块尚未发布到 Mooncakes；可以使用 GitHub 源码 workspace 或预览版原生二进制，见 README 和发行文档。
- 采用 Apache-2.0，依赖和样例保留各自许可证；完整依赖来源见 `THIRD_PARTY.md`。
