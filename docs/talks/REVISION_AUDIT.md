# TypeWhale 开发反复修改复盘

2026-09-05｜公开课事实底稿｜负责人：本轮资料审阅者。读者：产品负责人及分享策划。状态：回顾性提炼，不是产品承诺或本轮测试报告。根据新证据及本人回忆更新，制作PPT前复核。

本轮从**165份文档的全文读取与检索**出发，以旧开发日志的641个二级记录节为主线，对照现行七份文档、预览沟通/审计、专项规格/计划、模型评测及构建记录，整理出**35类问题与迭代主题、437条去重后的相关变更记录**。它们覆盖首次接入、修补、回退、体验调整、诊断实现和路线淘汰，**不是437次失败，也不是35个单一bug**。

阅读边界：全部文件已纳入全文读取和检索，主题相关的过程、决定和失败段落作重点精读；没有逐行人工复审所有计划中的示例代码，也没有逐条重放所有历史测试。此次是可追溯的记录级统计，不能声称已经穷尽仓库每一次实际修改。

## 怎么理解“改了多少次”

- 同一变更在规格、计划、开发日志、构建日志重复出现，只计开发日志的一条主记录。一个记录只归一个主主题，避免跨类重复相加。
- 一个日志节内多次补丁、回退合并计1条。因此下面的数字是**相关变更记录数，作为修改轮次的保守近似**，不等于精确提交数或编译数。例如L778包含789、790、791、792四次构建过程，仍只算1条；L799包含多项Task及热修，也只算1条。
- 新功能第一版也纳入，方便看完整来路；不把所有新增功能都说成返工。纯方案、纯测试/验收、只升级版本或重复安装的节不纳入这张变更表；有实际诊断代码或UI改动的记录可以纳入。
- 部分日期/build存在并发、倒序补记和复用。不能用“895减最初build”算修改次数，过程先后以具体记录内容为准。
- 其余204个二级节未作为独立变更计入：其中有发布汇总、计划讨论、测试审计、重复说明和本表未覆盖的其他工作。未纳入不等于无价值或没有实现。
- 文档字数：中文汉字504,704；去空白字符2,352,025，后者包含英文、数字、代码和标点，不能称作同样数量的“汉字”。165份含上一轮故事稿，后者不作为历史修改证据。
- 文件范围冻结于本轮读取快照；另一session未跟踪的`docs/stories/`不计入，不读写其内容。明细见[覆盖清单](REVISION_DOCUMENT_INVENTORY.md)，逐条证据见[CSV证据表](REVISION_EVIDENCE.csv)。

## 最集中的反复在哪里

| 主题 | 去重相关记录 | 最明显的反复 |
| --- | ---: | --- |
| 实时预览、长录音及最终文本交付（01+02） | 50 | 快照切分、文字缺失、缓存权威、停止补尾，多次回退 |
| OpenClaw消息界面及滚动（22+23） | 43 | 胶囊改聊天，身份、轮次、加载、滚动与窗口生命周期逐步补齐 |
| 智能整理/提示词（08） | 34 | 整理不足和过度改写之间反复；保真门与样例污染出现反作用 |
| 在线/旁路预览（34） | 33 | 很多是新架构实施，不是33次同一缺陷失败 |
| 截图选区、翻译、状态及工具（16–19） | 32 | 交互边界互相误伤，OCR超时需从请求结构解决 |
| TTS路线及ZipVoice质量（24+25） | 30 | 多模型试用淘汰，技术通过仍需真实听感 |
| 胶囊动效/显示（28） | 23 | 闪烁、跳字、形变，换皮肤没有恢复旧体验 |
| 麦克风采集与路由（05） | 21 | UI选择成功但硬件没采到，蓝牙/通道/总线不同 |
| 主窗口及设置（29） | 21 | 结构调整、约束残留和滚动位置反复 |

这些是不同粒度的主题归类，不适合直接比较哪个模块“工程能力最差”。它们适合帮助挑选故事和找反复产生的机制。

## 35类问题：为何改、怎样反复、最后去哪了

### 01｜实时预览：分块、缺字、回退与长录音（31条）

**为什么改：**想同时获得快速出字、上下文完整和长时间稳定，原先累计整段重识别逐渐吃力；短停顿切块又破坏上下文。

**修改过程：**累计快照→短停顿分块→回退1.2→长录音/重叠校正实验→修覆盖空洞、调度和数据权威；45秒限制撤回，1.2秒切块也撤回。

**最终去向：**现行文档：完整转录与约160字显示投影分离；普通录音上限5分钟，重叠矫正默认关闭。不能据此声称多小时稳定或所有缺字已根治。 **状态：主线已有落地；长录音全面验收仍不足。**

证据（与CSV逐条对应）：[L13159]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13159)、[L12697]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12697)、[L12666]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12666)、[L12547]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12547)、[L12514]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12514)、[L12480]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12480)、[L12027]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12027)、[L11987]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11987)、[L11945]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11945)、[L11904]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11904)、[L11859]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11859)、[L11827]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11827)、[L2402]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2402)、[L2382]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2382)、[L2354]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2354)、[L2333]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2333)、[L2308]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2308)、[L2287]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2287)、[L2244]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2244)、[L2225]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2225)、[L2179]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2179)、[L1472]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1472)、[L1463]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1463)、[L1456]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1456)、[L956]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:956)、[L778]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:778)、[L750]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:750)、[L742]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:742)、[L692]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:692)、[L677]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:677)、[L661]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:661)。

### 02｜停止后交付：屏幕有字却不粘贴、预览与最终结果不一致（19条）

**为什么改：**实时内容、旁路候选、整段重识别和可见尾巴都曾争夺“最终答案”的位置；缓存门槛会把已有文字判成不可交付。

**修改过程：**短/空结果用预览救回→候选缓存与整段识别多次换权威→缓存开关严格执行→已有文本允许交付并排空队列→按用户选择的ASR决定最终路径。

**最终去向：**现行：选择SenseVoice且关闭停止重识别时可用完整实时缓存；选择其他ASR时必须执行所选模型整段识别，不偷换为SenseVoice；失败明确反馈、不误粘贴。 **状态：当前规则明确；部分故障注入历史未通过。**

证据（与CSV逐条对应）：[L1193]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1193)、[L1203]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1203)、[L1211]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1211)、[L1113]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1113)、[L1105]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1105)、[L1098]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1098)、[L1090]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1090)、[L1080]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1080)、[L1072]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1072)、[L1064]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1064)、[L1030]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1030)、[L1020]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1020)、[L1009]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1009)、[L998]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:998)、[L942]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:942)、[L831]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:831)、[L799]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:799)、[L442]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:442)、[L436]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:436)。

### 03｜静音幻觉与轻声误伤（6条）

**为什么改：**静音会出现“The”“我”等字；过滤太狠又会吞掉轻声和真实短句。

**修改过程：**手写能量/噪声规则→Silero→补实时路径→短词过滤与最终人声门；7月后仍出现VAD误杀及短词稳定门回退。

**最终去向：**Silero负责语音判断，波形能量不作为唯一人声证据；未知短词不能仅因短就删除。这里的计数不重复计入第01、02类的VAD热修。 **状态：仍有边界风险，不能宣称静音零幻觉。**

证据（与CSV逐条对应）：[L17125]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:17125)、[L14020]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:14020)、[L13186]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13186)、[L13236]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13236)、[L8381]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8381)、[L10617]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10617)。

### 04｜停顿自动结束：抢先结束、迟迟不结束、与手动结束冲突（9条）

**为什么改：**慢说、起始静音、迟到VAD结果、采样被覆盖、手动按键与自动结束相撞。

**修改过程：**调整等待→独立任务与会话身份→两次无声确认→小型FIFO防漏采样→按有效采样时间计算。

**最终去向：**自动结束与预览开关解耦；手动结束及硬上限保留，VAD异常不能把整个输入流程关掉。 **状态：已落地的防护；自然说话体验需持续验收。**

证据（与CSV逐条对应）：[L16751]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16751)、[L16788]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16788)、[L16172]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16172)、[L16132]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16132)、[L2624]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2624)、[L2600]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2600)、[L2576]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2576)、[L2546]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2546)、[L2526]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2526)。

### 05｜麦克风：选了没声音、蓝牙路由、切换崩溃（21条）

**为什么改：**UI选择不等于底层真的绑定；设备采样率/通道/音频总线不同，语音处理与蓝牙切换会导致零帧或重启。

**修改过程：**入口删除后恢复并折叠→热切换→恢复风暴和格式修补→独立AUHAL→禁用/移除Apple语音处理→修系统默认、多通道及蓝牙内建麦克风策略。

**最终去向：**保留手动选择与跟随系统的明确区别；用底层真实采集结果核验。现行不能解释为所有设备都已验收。 **状态：多轮实修；全设备矩阵未完成。**

证据（与CSV逐条对应）：[L15885]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:15885)、[L15741]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:15741)、[L15719]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:15719)、[L1534]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1534)、[L1525]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1525)、[L1515]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1515)、[L1508]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1508)、[L1500]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1500)、[L1495]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1495)、[L1486]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1486)、[L1482]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1482)、[L8981]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8981)、[L9012]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9012)、[L1175]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1175)、[L1154]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1154)、[L1310]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1310)、[L1301]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1301)、[L1294]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1294)、[L988]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:988)、[L979]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:979)、[L968]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:968)。

### 06｜模型内存：省下来以后第一句话变慢（4条）

**为什么改：**模型缓存增长，但卸载会让下一次输入重载卡顿。

**修改过程：**90秒空闲卸载→取消定时卸载→高内存时释放后立即热加载→固定阈值改动态阈值。

**最终去向：**平时保持热加载；仅空闲且达到min(20GB,max(2GB,物理内存25%))时flush并热加载，冷却30秒。 **状态：已明确取舍：响应优先。**

证据（与CSV逐条对应）：[L13285]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13285)、[L13118]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13118)、[L12975]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12975)、[L12090]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12090)。

### 07｜空闲发热、主线程卡顿与错误省电（5条）

**为什么改：**高频轮询、重复热键启动/资源恢复、磁盘容量查询及不同timer混在一起；降频又误伤动画或唤醒。

**修改过程：**堵重复循环→调整阈值→拆后台/录音/动画timer→撤后台轮询→主线程磁盘查询移后台并限频。

**最终去向：**用独立职责和有界后台工作控制资源；不能用历史短时CPU数字证明过夜或全部长录音稳定。 **状态：局部证据充分；长期体验有待持续观察。**

证据（与CSV逐条对应）：[L12334]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12334)、[L12276]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12276)、[L12236]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12236)、[L12202]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12202)、[L2266]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2266)。

### 08｜智能整理：照抄、加戏、漏约束、把口述当提问回答（34条）

**为什么改：**“忠实”与“有效整理”被写成互相冲突的规则；开发模板套普通短句、固定测试答案进入公共提示词、保真检查误拒正确改写、用户情绪被抹平。

**修改过程：**堆模板与例子→分模式/恢复旧好体验→补硬约束→删除/恢复聊天模式→加入又撤销语义保真闸门→清掉样例污染、放松照抄倾向→明确只整理不代答。

**最终去向：**以信息完整、保留意图和必要情绪为核心；非空结果不再经过那套语义忠实度硬拦截，错误/空结果/协议/超时边界仍在。 **状态：持续校准，最新仍有“不要代答”修正。**

证据（与CSV逐条对应）：[L12735]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12735)、[L8219]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8219)、[L8176]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8176)、[L8126]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8126)、[L8084]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8084)、[L8044]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8044)、[L7825]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7825)、[L7785]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7785)、[L7661]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7661)、[L7558]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7558)、[L7520]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7520)、[L7486]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7486)、[L7457]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7457)、[L7413]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7413)、[L7362]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7362)、[L7303]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7303)、[L7252]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7252)、[L7143]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7143)、[L6771]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6771)、[L5416]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5416)、[L5378]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5378)、[L5344]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5344)、[L732]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:732)、[L722]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:722)、[L712]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:712)、[L394]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:394)、[L387]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:387)、[L373]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:373)、[L364]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:364)、[L337]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:337)、[L326]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:326)、[L314]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:314)、[L264]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:264)、[L34]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:34)。

### 09｜本地智能模型路线：接入以后并不等于适合产品（14条）

**为什么改：**可下载、可运行、参数大都不能证明整理语义与日常延迟合格；自动换大模型会破坏热态。

**修改过程：**MiniMax接入后因语义表现撤下→Ollama多次试模型→GPT-OSS测试后只作可选接入→收敛Qwen直连MLX。

**最终去向：**受管本地整理Qwen3-4B-Instruct-2507四比特与云端DeepSeek v4flash；Ollama/GPT-OSS从产品路径退役，用户外部安装不删除。 **状态：路线已收敛；不等于旧模型普遍无价值。**

证据（与CSV逐条对应）：[L10659]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10659)、[L10575]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10575)、[L10533]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10533)、[L10481]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10481)、[L10442]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10442)、[L10395]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10395)、[L8905]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8905)、[L8833]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8833)、[L8791]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8791)、[L1415]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1415)、[L1431]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1431)、[L533]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:533)、[L513]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:513)、[L497]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:497)。

### 10｜Qwen速度与缓存：预热了还是慢，缓存也会出错（6条）

**为什么改：**公共长提示词反复计算；缓存深拷贝/裁剪失效、唤醒竞态、启动预填充不完整。

**修改过程：**前缀缓存→失败单次完整重算→真实裁剪与字节预算→启动预填充→睡眠唤醒与正常唤醒预热修复。

**最终去向：**有界前缀复用与受管worker；历史实测热缓存中位118ms指worker场景，不能包装成App所有请求延迟。 **状态：已有局部性能证据。**

证据（与CSV逐条对应）：[L488]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:488)、[L479]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:479)、[L471]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:471)、[L463]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:463)、[L457]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:457)、[L452]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:452)。

### 11｜模型下载与设置页：看见进度不等于真下载（13条）

**为什么改：**长标题挤掉按钮、约束冲突、0%假进度、进程同步等待使启动/取消卡住，残留空目录造成误判。

**修改过程：**固定列布局反复修宽度→恢复真实下载→真实停止→启动清理→异步下载与取消。

**最终去向：**现行模型页以实际文件/任务状态显示就绪和进度；旧Ollama专属实现随路线退役。 **状态：基础问题已修，部分机制已替换。**

证据（与CSV逐条对应）：[L6502]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6502)、[L6479]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6479)、[L6453]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6453)、[L6430]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6430)、[L6406]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6406)、[L6373]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6373)、[L6339]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6339)、[L6307]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6307)、[L6278]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6278)、[L6241]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6241)、[L6178]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6178)、[L6150]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6150)、[L6105]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6105)。

### 12｜ASR多模型：从“列出来”到真能运行，再做淘汰（15条）

**为什么改：**发现目录不是可推理；标点模型未用、符号链接误判、热词参数不支持会退出进程，选项太多带来质量与UI成本。

**修改过程：**列候选→补真实后端/预热→热词上限→符号链接→崩溃隔离→Zipformer准入→筛掉6个产品候选。

**最终去向：**当前保留SenseVoice、Parakeet TDT v2、FunASR Nano、Qwen3ASR 0.6B/1.7B；不把所选模型失败藏在另一模型后面。 **状态：产品候选收敛，不是所有模型绝对排名。**

证据（与CSV逐条对应）：[L1407]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1407)、[L1397]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1397)、[L1385]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1385)、[L1377]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1377)、[L1369]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1369)、[L1363]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1363)、[L1357]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1357)、[L1350]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1350)、[L1343]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1343)、[L1334]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1334)、[L1325]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1325)、[L1319]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1319)、[L1440]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1440)、[L1448]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1448)、[L416]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:416)。

### 13｜粘贴目标：防误操作却挡住微信、复制到旧内容（8条）

**为什么改：**前台窗口会变、AX可编辑判定不可靠、剪贴板写入与模拟粘贴有竞争。

**修改过程：**跟踪真实目标→不猜前一个App→可编辑检查→微信特例放宽→撤掉阻断白名单→目标快照→剪贴板就绪与抢占判定。

**最终去向：**保留目标/会话保护；不再用那套过严AX门槛阻挡正常输入；粘贴要确认拿到本轮剪贴板。 **状态：防护已调整，跨App体验仍需真实验证。**

证据（与CSV逐条对应）：[L13487]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13487)、[L13512]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13512)、[L13429]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13429)、[L13360]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13360)、[L13338]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13338)、[L13316]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13316)、[L8713]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8713)、[L5260]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5260)。

### 14｜Reader误朗读：一次来源标记修复还不够（2条）

**为什么改：**架构迁移漏了来源标记；修回标记后，0.3秒恢复剪贴板快于Reader约0.6秒轮询，Reader仍读旧文本。

**修改过程：**先恢复原子写入文字+来源→发现时序缺口→按恢复文本的SHA256指纹排除自家恢复，正常新复制仍可读。

**最终去向：**来源标记与恢复指纹共同工作。 **状态：有明确首次修复不足的证据。**

证据（与CSV逐条对应）：[L129]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:129)、[L123]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:123)。

### 15｜自动发送：倒计时位置、取消和重复回车（7条）

**为什么改：**用户需要按App选择自动发送，又要随时撤销；手动回车后定时器再回车；“居中”只做到横向。

**修改过程：**按App启用→1.5秒可取消→2秒→手动Enter取消→整条可点取消→双轴居中→1–10秒配置。

**最终去向：**默认关闭，按App配置，默认2秒；倒计时可整条取消，手动发送终止待发送任务。 **状态：交互规则已收敛。**

证据（与CSV逐条对应）：[L596]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:596)、[L585]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:585)、[L576]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:576)、[L524]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:524)、[L356]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:356)、[L349]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:349)、[L116]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:116)。

### 16｜截图选区：窗口选择和自由框选互相干扰（9条）

**为什么改：**点窗口和拖框共用手势；窗口候选锁定误延伸到普通框选；工具按钮鼠标事件、冻结时机不同。

**修改过程：**延后判定点击/拖拽→窗口框移动→拖拽转普通选择→普通选区曾锁定→恢复边框拖拽；补冻结和工具事件。

**最终去向：**保留普通框选的调整能力；窗口候选和拖框明确分工。最后具体视觉需按当前安装版验收。 **状态：出现过主动改向与恢复旧体验。**

证据（与CSV逐条对应）：[L13606]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13606)、[L13386]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13386)、[L12130]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12130)、[L11609]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11609)、[L11578]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11578)、[L11508]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11508)、[L11446]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11446)、[L11233]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11233)、[L11260]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11260)。

### 17｜截图翻译：覆盖位置、重复OCR与超时（8条）

**为什么改：**整卡翻译挡画面；OCR行重复使请求变长；统一短超时不足，增加时间仍不能解决大批量。

**修改过程：**整卡→按OCR行坐标→字号自适应→行ID协议→恢复横坐标→67行去重至35行→分档超时→分块翻译。

**最终去向：**独立截图提示词与行ID/位置映射；支持分块处理；双语对照P3不能因有文档就说已完成。 **状态：核心路径迭代；不等于全部布局和语言通过。**

证据（与CSV逐条对应）：[L13063]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13063)、[L13046]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13046)、[L13026]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13026)、[L11538]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11538)、[L9431]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9431)、[L6630]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6630)、[L6583]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6583)、[L6536]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6536)。

### 18｜截图状态与主窗口：修A造成B失效（10条）

**为什么改：**防止截图抢焦点时一刀切屏蔽主窗口；状态门禁误禁普通截图工具；异步OCR token与提示状态串用。

**修改过程：**禁reopen→Esc隐藏→Dock打不开再修→彻底解耦截图与主窗口→显式状态→恢复工具栏→OCR独立token→再修复制回调。

**最终去向：**截图独立生命周期；Dock/主动打开主窗口保留；OCR结果用本操作身份判断。 **状态：典型跨功能回归链。**

证据（与CSV逐条对应）：[L12162]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12162)、[L10766]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10766)、[L10952]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10952)、[L8625]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8625)、[L8539]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8539)、[L9536]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9536)、[L9502]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9502)、[L9466]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9466)、[L9304]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9304)、[L7186]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7186)。

### 19｜截图工具：工具栏挤出界面与标注编辑取舍（5条）

**为什么改：**新增工具使12按钮宽度超过容器；用户希望标注不被误选拖动，改用撤销/前进；蒙层和笔色影响辨识。

**修改过程：**移除标注选中/拖动，增加前进→工具栏响应式→高斯马赛克→调整蒙层/笔工具。

**最终去向：**普通选区调整与内部标注是两件事：内部标注不可拖动，通过撤销/前进修正；本类按明确实现记录计，不将所有截图计划视为完成。 **状态：已记录实现；历史布局非当前视觉认证。**

证据（与CSV逐条对应）：[L5063]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5063)、[L5110]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5110)、[L5144]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5144)、[L11476]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11476)、[L11064]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11064)。

### 20｜归档与闪念：入口、整理模式、内容与文件不一致（14条）

**为什么改：**普通语音与归档并发状态互相覆盖；默认整理模式多次取舍；文字归档遗漏原图；用户一句“现在”被误解为目录名。

**修改过程：**每日归档→开发者默认→可配置并默认穷尽→任务隔离/结束修复→闪念独立模式与反馈→原图随归档保存并放附件子目录。

**最终去向：**归档与普通输入拥有独立任务；闪念按独立配置处理，保留截图附件。原“默认开发者”等只是中间方案。 **状态：已落地，含需求理解纠偏。**

证据（与CSV逐条对应）：[L5548]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5548)、[L5517]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5517)、[L5475]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5475)、[L5708]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5708)、[L5681]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5681)、[L5635]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5635)、[L5603]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5603)、[L5575]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5575)、[L5313]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5313)、[L5227]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5227)、[L5185]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5185)、[L5035]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5035)、[L4978]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4978)、[L4910]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4910)。

### 21｜OpenClaw通信：终端能用、GUI不能用，回复拿错字段（6条）

**为什么改：**GUI PATH不同，JSON外层状态被当回复；升级Node后仍挑到旧NVM版本；探测环境污染语音worker。

**修改过程：**纠正回复字段→补GUI PATH→选兼容Node→探测收窄到CLI→每候选0.5秒超时并处理管道。

**最终去向：**Node每次CLI调用重新验证、有界探测；OpenClaw回复不直接写回前台输入框。 **状态：截至Build895的最近主线修复。**

证据（与CSV逐条对应）：[L4490]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4490)、[L4345]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4345)、[L4286]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4286)、[L7]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7)、[L14]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:14)、[L21]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:21)。

### 22｜OpenClaw对话：布局、气泡、身份和轮次反复（31条）

**为什么改：**最初把回复塞进胶囊后功能越加越多；共用控件、全局loading、无轮次身份造成消失、错认和串消息；短标题也有测量错误。

**修改过程：**控件拆开→胶囊→聊天气泡→身份/颜色→用户消息→加载过渡→turnID→按整个对话生命周期管理→折叠球。

**最终去向：**按对话轮次管理用户/状态/回复；CLI最终JSON的递进播放不能说成真实模型流式输出。 **状态：多次产品成形与缺陷修复并存。**

证据（与CSV逐条对应）：[L4461]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4461)、[L4432]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4432)、[L4403]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4403)、[L4375]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4375)、[L4315]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4315)、[L4254]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4254)、[L4223]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4223)、[L4186]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4186)、[L4152]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4152)、[L4126]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4126)、[L4098]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4098)、[L4062]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4062)、[L4029]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:4029)、[L3992]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3992)、[L3956]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3956)、[L3924]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3924)、[L3877]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3877)、[L3842]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3842)、[L3795]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3795)、[L3738]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3738)、[L3687]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3687)、[L3644]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3644)、[L3605]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3605)、[L3560]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3560)、[L3514]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3514)、[L3430]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3430)、[L3029]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3029)、[L1997]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1997)、[L1964]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1964)、[L1950]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1950)、[L569]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:569)。

### 23｜OpenClaw滚动：底部裁切、跳动、最新长消息看不到开头（12条）

**为什么改：**滚动坐标、气泡宽度、自动reveal和重新渲染互相竞争；新消息、长回复与用户阅读意图冲突。

**修改过程：**底部追加→容器/宽度→最新消息→超长消息起点→状态原位替换→顶部坐标→链接→解除多次滚动竞争。

**最终去向：**以清晰的最新消息展示与稳定滚动为目标；不能将某次源码守卫通过视为所有长对话视觉通过。 **状态：历史多轮修复，需长对话真实验收。**

证据（与CSV逐条对应）：[L3471]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3471)、[L2961]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2961)、[L2898]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2898)、[L2868]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2868)、[L2842]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2842)、[L2814]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2814)、[L2789]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2789)、[L2761]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2761)、[L2733]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2733)、[L2704]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2704)、[L2682]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2682)、[L2655]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2655)。

### 24｜TTS路线：能出声到能连续、稳定、听得下去（20条）

**为什么改：**首包慢、管道死锁、第三轮串到主输入、退出崩溃、只播部分内容；模型下载成功不等于声线合格。

**修改过程：**Qwen TTS→Melo→Sherpa并行→八模型实验台→真实资格测试→声线筛选→ZipVoice-only。

**最终去向：**当前TTS只保留ZipVoice；旧模型评测数据保留。TTS仍有Python运行时，不应称已完全原生。 **状态：多路线淘汰后收敛。**

证据（与CSV逐条对应）：[L2451]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2451)、[L2159]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2159)、[L2129]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2129)、[L2089]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2089)、[L2056]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2056)、[L2048]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2048)、[L2042]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2042)、[L2036]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2036)、[L2030]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2030)、[L2019]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2019)、[L2011]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2011)、[L299]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:299)、[L291]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:291)、[L284]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:284)、[L279]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:279)、[L273]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:273)、[L253]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:253)、[L240]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:240)、[L232]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:232)、[L223]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:223)。

### 25｜ZipVoice音质与个人声线：指标变好但人声不像了（10条）

**为什么改：**长参考有前缀嘶声；短参考减少噪声却损失音色；PCM格式错误产生噪声；只有引号的分块让播报预取停掉。

**修改过程：**短参考规则→真实听感不合格回退→盲听校准参考→DSP→长文本规范化→个人声线→修录音上限/PCM→OpenClaw自然分块及空块容错。

**最终去向：**四个参考声线与合格个人声线；TTS合成长文处理与OpenClaw的60–100字准备分块须区分。 **状态：听感是重要验收；个别参考保留例外。**

证据（与CSV逐条对应）：[L200]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:200)、[L194]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:194)、[L187]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:187)、[L179]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:179)、[L172]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:172)、[L165]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:165)、[L157]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:157)、[L151]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:151)、[L144]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:144)、[L136]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:136)。

### 26｜录音期间电脑声音：恢复太突兀、越录越小、误播放（6条）

**为什么改：**降音量打断体验、恢复覆盖手动调音量；连续录音拿已降低音量当基准；盲目媒体toggle会把暂停音乐播放起来。

**修改过程：**降到5%→尊重手动音量→延迟渐恢复→首次基准→有状态且同进程拥有的暂停/恢复→降到0。

**最终去向：**录音静音；恢复遵守用户新意图；媒体状态未知不盲切。MediaRemote兼容性仍需跨播放器实测。 **状态：需求与状态保护逐步收敛。**

证据（与CSV逐条对应）：[L15662]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:15662)、[L15605]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:15605)、[L15496]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:15496)、[L69]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:69)、[L60]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:60)、[L48]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:48)。

### 27｜快捷键与鼠标侧键：唤醒丢第一次、按键串义、穿透前台（15条）

**为什么改：**热键capture吞第一下Fn；事件tap失活；普通数字键与鼠标侧键混淆；第六键设备映射不同；已绑定点击仍传给前台。

**修改过程：**备用/媒体键→初始化修复→右Option精确判定→空闲健康复核→唤醒宽限→侧键接入/编译修补/映射修正→消费已绑定事件。

**最终去向：**已匹配侧键不穿透；未绑定键保持系统行为；快捷键配置以真实当前绑定为准。 **状态：包含编译返工与真实设备兼容修复。**

证据（与CSV逐条对应）：[L13100]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13100)、[L13139]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13139)、[L11029]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11029)、[L11088]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11088)、[L9801]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9801)、[L1424]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1424)、[L609]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:609)、[L111]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:111)、[L107]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:107)、[L102]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:102)、[L97]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:97)、[L92]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:92)、[L87]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:87)、[L82]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:82)、[L41]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:41)。

### 28｜胶囊动效：想更丝滑，却闪烁、跳字、形状变形（23条）

**为什么改：**整个文本替换与逐字动画冲突，长度变化影响布局；统一刘海/无刘海几何困难；换皮肤误代替恢复真实旧体验。

**修改过程：**整体淡入→逐字→恢复1.2局部呈现→分内容/动效→多窗口改统一形状→弹性收起再纠偏→统一路径/遮罩→黑色极简历史体验恢复。

**最终去向：**UI负责显示投影，不拥有完整转录；显示开关不决定识别数据；黑色胶囊以真实交互机制而非只换颜色验收。 **状态：可见体验需安装版复核。**

证据（与CSV逐条对应）：[L16642]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16642)、[L16672]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16672)、[L16698]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16698)、[L16719]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16719)、[L16817]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16817)、[L16152]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:16152)、[L12608]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12608)、[L12580]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12580)、[L1219]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1219)、[L1225]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1225)、[L10169]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10169)、[L10153]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10153)、[L10135]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10135)、[L10116]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10116)、[L10099]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10099)、[L9761]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9761)、[L9675]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9675)、[L9607]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9607)、[L9570]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9570)、[L652]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:652)、[L642]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:642)、[L633]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:633)、[L625]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:625)。

### 29｜主窗口与设置：布局越改越挤、滚动修正又撤回（21条）

**为什么改：**从竖向到三栏时尺寸/约束残留；当前与历史区高度意图被理解反；设置控件多、滚动坐标和用户阅读位置被强制重置。

**修改过程：**横向布局→尺寸回正→卡片预算→设置移位/折叠→Classic Mac设置→翻转坐标/层级→两次复位修补后取消复位。

**最终去向：**保留用户滚动位置；功能入口与布局以现行设计文档为准。不能把每次审美调整都叫bug。 **状态：含产品偏好调整与真实布局缺陷。**

证据（与CSV逐条对应）：[L13953]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13953)、[L13929]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13929)、[L13905]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13905)、[L13888]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13888)、[L13842]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13842)、[L13748]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13748)、[L13729]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13729)、[L12924]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12924)、[L12886]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12886)、[L12866]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12866)、[L12842]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12842)、[L12822]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12822)、[L7103]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7103)、[L7068]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7068)、[L7033]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7033)、[L6993]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6993)、[L6951]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6951)、[L6910]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6910)、[L6876]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6876)、[L6838]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:6838)、[L7605]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:7605)。

### 30｜品牌与概念素材：图标被覆盖、预览不代表真实UI（7条）

**为什么改：**启动动画轮廓不符品牌，图标尺寸不合适；另一轮改动覆盖已确认图标；手绘主题预览与生产效果不一致。

**修改过程：**采用透明视频→恢复黄鲸→放大图标→再次恢复被覆盖图标→预览改真实快照→概念画廊移出生产源码。

**最终去向：**概念素材与真实产品分开；已批准品牌资产需保护。 **状态：有明确并发覆盖与预览失真证据。**

证据（与CSV逐条对应）：[L3065]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:3065)、[L1270]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1270)、[L1254]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1254)、[L771]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:771)、[L562]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:562)、[L555]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:555)、[L28]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:28)。

### 31｜成本与重复实例：先限制用户，后来发现幽灵进程（3条）

**为什么改：**用户感到花费异常；先用日限额解决，用户指出影响工作；日志与服务器费用差距暴露未记账旧进程。

**修改过程：**日常硬限额→只防异常→查出长时间残留实例及重复快捷键请求→加强单实例与退出处理。

**最终去向：**成本治理要先识别异常调用，不能拿正常工作配额代替根因调查；现行云端费用仍取决于用户所选服务。 **状态：典型错误归因后被证据纠正。**

证据（与CSV逐条对应）：[L13806]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13806)、[L13771]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13771)、[L13456]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13456)。

### 32｜Ollama生命周期：后台启动、关了又活过来（3条）

**为什么改：**启动桌面App会抢焦点；重复启动、旧进程不健康、退出时在途请求又拉起服务。

**修改过程：**无头serve单飞启动→记录自家PID并止损重启→退出不可逆闩锁。

**最终去向：**这些修复属于历史Ollama阶段；现行产品已移除Ollama路径，不能继续作为当前架构说明。 **状态：已被后续模型路线替代。**

证据（与CSV逐条对应）：[L702]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:702)、[L684]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:684)、[L670]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:670)。

### 33｜异步架构：上一轮结果污染下一轮（5条）

**为什么改：**录音、识别、整理、粘贴散在协调器，取消和晚到回调难以区分任务。

**修改过程：**任务身份→流程状态机→录音/识别身份边界→FinalRecognition提取→命令分发。

**最终去向：**会话/操作身份与分层边界成为现行约束；只列有实现证据的切片，不把整份架构计划算完成。 **状态：逐步落地；非“一次重构全好了”。**

证据（与CSV逐条对应）：[L15630]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:15630)、[L15686]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:15686)、[L9128]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9128)、[L9084]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9084)、[L9367]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9367)。

### 34｜在线/旁路预览：搭起框架后才暴露真数据问题（33条）

**为什么改：**起初旁路复用旧快照，不能证明新模型成立；真实设备48k与fixture16k不同，MiMo重复前缀/缩短回退，慢推理拖累UI。

**修改过程：**独立领域状态/会话/广播→真实provider→网络协议/密钥→采样率修正→候选内容与动效分离→真实SenseVoice→累计内容→慢推理自熔断。

**最终去向：**旁路实验不自动获得生产/最终粘贴权威；MiMo曾有真实Key证据，豆包不能把缺Key测试写成实测成功。 **状态：基础框架与切片落地；历史NO-GO须保留。**

证据（与CSV逐条对应）：[L1929]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1929)、[L1919]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1919)、[L1908]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1908)、[L1897]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1897)、[L1886]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1886)、[L1863]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1863)、[L1847]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1847)、[L1817]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1817)、[L1807]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1807)、[L1801]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1801)、[L1782]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1782)、[L1755]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1755)、[L1746]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1746)、[L1737]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1737)、[L1729]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1729)、[L1720]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1720)、[L1711]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1711)、[L1700]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1700)、[L1688]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1688)、[L1679]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1679)、[L1668]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1668)、[L1660]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1660)、[L1628]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1628)、[L1621]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1621)、[L1613]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1613)、[L1604]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1604)、[L1587]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1587)、[L1579]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1579)、[L1571]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1571)、[L1563]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1563)、[L1553]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1553)、[L1544]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1544)、[L1243]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1243)。

### 35｜兼容与打包：开发机可用，分发包却缺模型（2条）

**为什么改：**macOS12与所用原生依赖实际不兼容；打包排除大LLM时误删了基础ASR/VAD。

**修改过程：**macOS12支持尝试后放弃→明确系统边界；打包从删除Models整目录改为保留基础语音白名单。

**最终去向：**Windows只是独立历史基线，未验证对齐；本地895不等于公开下载895；分发仍需独立验收。 **状态：一项明确放弃，一项分发修复。**

证据（与CSV逐条对应）：[L14084]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:14084)、[L5442]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5442)。

## 可以讲清楚来龙去脉的十个转折

### 1. “模型不行，所以只能录45秒”被撤回

Build339还在处理长录音后段卡住，340把上限收紧到45秒；用户指出1.2曾能识别一两分钟，341撤回限制并保留诊断。后续真正发现的问题包括音频覆盖空洞、主线程磁盘查询、调度饥饿、整块删除导致前缀丢失和显示尾巴反向影响最终判定。它不是“换个参数就好了”。

公开课价值：用户对旧体验的记忆提供了反证，迫使团队重新查根因。最终现行上限五分钟；历史四小时实验不能当成已交付能力。证据：[原日志 L11904]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11904)、[原日志 L11859]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11859)、[原日志 L2266]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:2266)、[原日志 L742]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:742)、[现行架构](../current/ARCHITECTURE.md)。

### 2. 为了让字不再跳，反而把话切碎了

7月20日尝试“停顿1.2秒就收口”，想冻结说完的短句。第一轮VAD漏判又让普通快照不继续运行，热修允许ASR证据反哺；接着真实8–9秒录音在约3.4、5.4、7.5秒连续切块，用户反馈缺字少字，回退到10秒后停顿收口、18秒硬分块，再清掉实验残留。这个日志节实际包含4个build，而统计只计1条。

公开课价值：视觉稳定、语义确认、音频资源切块是不同问题，把它们绑在一个“停顿”参数上会制造新损失。证据：[原日志 L778]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:778)。

### 3. 160字的显示窗口，差点成了全部记忆

屏幕为了简洁只显示一段尾巴，但同类截短内容又进入停止判定与交付检查。另一处校准覆盖音频的后半段，却删除了仍保存前半段的整块。修复后用固定129.657秒录音回放：旧故障缓存638字，修后749字，整段识别751字，恢复111字。这里的“字”是日志中的字符数，不是人工逐字准确率。

公开课价值：界面只能看见一小段，不代表产品只拥有一小段。这组样本证明具体丢失有改善，不证明所有录音100%正确。证据：[原日志 L692]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:692)、[原日志 L677]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:677)、[原日志 L661]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:661)。

### 4. 一道“保真保险”，把正确答案拦在外面

智能整理为了不丢约束加入语义忠实度检查；模型将“不能”改为“不得”，检查却因缺少原词判失败，用户拿回原文，感受就是“又没整理”。Build839撤掉这套硬拦截。随后840加入通用结构却把固定样例带入公共提示词，841再次清掉污染；再往后还要纠正提示词太保守导致照抄。

公开课价值：规则写得更多不等于更可靠，测试也可能把错误目标固化。移除的是这套语义闸门，错误/空结果/超时处理仍保留。证据：[原日志 L712]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:712)、[原日志 L387]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:387)、[原日志 L373]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:373)、[原日志 L364]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:364)、[原日志 L314]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:314)。

### 5. 内存掉下来了，用户却更难用了

先用90秒空闲卸载减内存，用户久未说话后第一句变慢；于是取消定时卸载。高内存释放后仍保持冷态又有同样问题，进一步改为释放后马上热加载，再把阈值改为随物理内存变化。

公开课价值：优化指标要服从真实使用目标；“内存更低”不能脱离“开口就能用”单独庆祝。这是一项有成本的产品取舍，不是内存问题凭空消失。证据：[原日志 L13285]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13285)、[原日志 L13118]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13118)、[原日志 L12975]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12975)、[原日志 L12090]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12090)。

### 6. 防误粘贴的检查，让微信反而不能粘贴

先只允许标准AX文本控件，微信富文本框不按该角色暴露，系统Cmd+V本来能工作，产品却提前拒绝。Build240增加兼容路径，241撤掉最终粘贴前那套AX输入框判断。后来剪贴板竞争又要用“就绪/重试/被抢占”处理，不能把两种问题混成同一个焦点bug。

公开课价值：系统给出的抽象信号与用户实际可操作能力不总一致。证据：[原日志 L13338]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13338)、[原日志 L13316]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13316)、[原日志 L5260]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5260)。

### 7. “修好了”是真的，但没覆盖到那个时间差

Reader误读语音输入临时剪贴板：870补回迁移时丢失的来源标记，871发现临时文字约0.3秒就恢复，而Reader约0.6秒才轮询，看不见中间状态。第二次修复加入恢复文本指纹，才覆盖到这个时间差。

公开课价值：单个模块逻辑正确不等于端到端时序正确。两条记录可以明确讲成“第一次修复仍不足，第二次补齐另一条路径”。证据：[原日志 L129]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:129)、[原日志 L123]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:123)。

### 8. 为了不抢主窗口，连主动点Dock也打不开了

截图过程中主窗口不应突然出现，最早直接屏蔽reopen。之后用户主动点Dock也打不开，需要恢复明确主动入口；再后来从架构上拆除截图和主窗口显示的隐藏耦合。类似的回归发生在截图状态机：448增加门禁，449修正普通截图工具栏被误禁用。

公开课价值：不能用全局禁止代替精确区分“系统被动回调”和“用户明确操作”。证据：[原日志 L12162]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12162)、[原日志 L8625]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8625)、[原日志 L8539]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:8539)、[原日志 L9502]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9502)、[原日志 L9466]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:9466)。

### 9. 音频指标更好了，人却不像了

ZipVoice将10–15秒参考缩短至1–3秒以改善句首伪声；短参考技术指标改善，但视频音色变得不像原人，Build862做P0回退，保留15.453秒原参考作为例外。863继续盲听发现分句拼接虽改善音量爬升，却重置呼吸、语速、情绪，因此也没进入正式链路。

公开课价值：听感的关键维度不能被一个波形指标替代；规则可以有证据充分的例外。证据：[原日志 L200]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:200)、[原日志 L194]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:194)、[原日志 L187]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:187)、[原日志 L179]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:179)。

### 10. 想控制费用，先把正常工作限制住了

用户反馈费用高，先加每日限额和字数限制；用户指出软件是帮助工作，不能限制正常使用，于是转向异常调用保护。后续本地31次约1.9万token与服务端约37.1万token对不上，调查发现长时间残留的旧实例和重复热键请求，才转向单实例治理。

公开课价值：账单是症状，限制用户不是根因。这里是日志记载的那次差异，不是现行长期成本倍率。证据：[原日志 L13806]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13806)、[原日志 L13771]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13771)、[原日志 L13456]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13456)。

## 明确放弃、撤回或没有完成的东西

| 路线/决定 | 为什么停或改 | 后来去向 | 证据 |
| --- | --- | --- | --- |
| 45秒上限作为长音频修复 | 用户旧体验反证，根因不成立 | 撤回；现行五分钟 | [原日志 L11904]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11904)、[原日志 L11859]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11859) |
| 短停顿直接清空/切分上下文；1.2秒收口 | 语义上下文断裂、缺字 | 回退；分块边界另行治理 | [原日志 L13159]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13159)、[原日志 L12666]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12666)、[原日志 L778]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:778) |
| 未知两字结果必须重复出现 | 停止前只出现一次的“结束”被吞 | 回退；不能用长度消灭幻觉 | [原日志 L17125]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:17125)尾部7月21日追加 |
| 多小时长录音实验作为当前承诺 | 实验与生产、容量证据被混淆 | 旧实验退役；保留五分钟上限 | [预览沟通](../PREVIEW_ARCHITECTURE_COMMUNICATION_LOG.md)、[现行架构](../current/ARCHITECTURE.md) |
| 模型90秒空闲卸载 | 第一声变慢 | 改为高内存flush+热加载 | [原日志 L13118]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:13118)、[原日志 L12975]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:12975) |
| Apple麦克风语音增强路径 | 零帧、首字丢失，修补后仍影响采集 | 移除该路径 | [原日志 L1175]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1175)、[原日志 L1154]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1154)、[原日志 L1310]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1310) |
| MiniMax作为活动整理选择 | 当时实际语义表现不符合目标 | 当时下线，不能外推所有版本模型 | [原日志 L10395]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:10395) |
| GPT-OSS作为默认整理模型 | 隔离准入语义失败，架构通过不等于模型通过 | 曾允许可选接入，后从产品退役 | [准入报告](../research/2026-07-24-gpt-oss-local-admission.md)、[原日志 L533]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:533)、[原日志 L497]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:497) |
| Ollama作为当前受管整理路径 | 产品模型路线收敛 | Qwen直连MLX；历史生命周期修复仍可讲 | [原日志 L497]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:497)、[原日志 L702]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:702) |
| 六个ASR候选继续摆在产品菜单 | 稳定性/质量/产品适配不足 | 五个候选留下；不是全球性能榜 | [原日志 L416]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:416) |
| 多引擎TTS长期并列 | 下载、运行、声线、听感维度不一致，维护复杂 | 当前只留ZipVoice | [原日志 L253]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:253)、[原日志 L240]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:240)、[原日志 L223]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:223) |
| 所有克隆参考必须小于3秒 | 短参考使特定声线失真 | 长参考例外保留 | [原日志 L187]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:187) |
| TTS按句拼接直接进正式链路 | 跨句呼吸、速度和情绪重置 | 原场景保留整段合成；不混淆OC请求准备分块 | [原日志 L179]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:179)、[原日志 L136]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:136) |
| 截图普通选区完全锁死 | 用户需要二次调整 | 恢复普通选区拖拽；内部标注仍是另一套规则 | [原日志 L11508]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11508)、[原日志 L11446]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:11446)、[原日志 L5144]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:5144) |
| macOS12兼容 | 当时原生依赖ABI/系统兼容成本不可接受 | 放弃，恢复macOS14基线 | [原日志 L14084]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:14084) |
| 豆包真实Key、全部长录音/设备、Windows对齐、商业收入等完成声明 | 只有局部测试、计划或未验证资料 | 保持未核验，不能包装成功 | [在线readiness](../ONLINE_STREAMING_PROVIDER_READINESS.md)、[发布验收](../current/RELEASE_QA.md)、[商业现状](../current/COMMERCIAL.md) |

## 为什么总在反复：跨主题归纳

以下是基于记录的分析，不是对当事人心理的推断。

1. **先修表象，后发现真正边界。** 卡顿先改间隔/时长，后来才发现主线程I/O、音频范围所有权；“没粘贴”既可能是目标错误，也可能是缓存为空或剪贴板竞争。
2. **修复范围大于问题范围。** 防截图抢焦点却禁了Dock；VAD防幻觉却关了普通ASR；来源标记修复没有覆盖恢复时序。需要精确界定一项修复影响什么。
3. **把用户体验问题简化成一种指标。** 内存低但起步慢、短参考波形好但不像、所有检查绿灯但真实录音仍缺字。编译/测试/主观体验各自证明不同事情。
4. **需求理解偏移。** “黑色主题”被实现成换皮肤而非恢复旧机制；“整理”被理解成照抄或替用户回答；“保留情绪”被当成不必要词句删掉。这类返工属于产品理解，不是纯技术难题。
5. **功能长出来了，身份与状态模型没一起长。** OpenClaw从一条回复成长为多轮对话，仍共用loading就会串轮次；语音/截图/归档并发后，全局状态容易让上一轮结果污染下一轮。
6. **历史好体验和已确认资产没有被稳固保护。** 1.2体验多次被要求找回；黄色图标被后续改动覆盖；新旧文档都说“当前”造成判断混乱。现行七文档和并发保护是对此的治理回应。
7. **一部分反复是合理学习。** 归档默认模式、媒体静音、窗口形态、模型保留名单，是经过使用才有答案的取舍；不能为了戏剧性把它们全部改写成失败。

## 哪些成就可以有证据地讲

- 一段固定长录音故障缓存从638到749字符，明确找回111字符；不是只说“感觉好多了”。[原日志 L661]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:661)。
- 模型选择开始尊重用户明确选择，失败也不偷换模型制造成功。[原日志 L442]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:442)及[现行架构](../current/ARCHITECTURE.md)。
- 麦克风问题从“设置选中了”推进到检查真实帧数、采样率、通道和总线。[原日志 L1525]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1525)、[原日志 L1482]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1482)、[原日志 L1294]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:1294)。
- TTS资格从“下载了八个模型”升级为固定中英混合/长文验证、声线资格与真人盲听；最后敢于缩减产品名单。[原日志 L253]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:253)、[原日志 L240]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:240)、[原日志 L223]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:223)。
- 提示词从追求整齐模板，转向保留信息、约束、用户情绪和判断；明确软件是在帮助表达。[原日志 L264]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:264)、[原日志 L34]($HOME/Pictures/macOSwinOSCoding/TypeSpeaker/docs/开发日志.md:34)。
- 从把历史计划当现状，转到保留失败证据、区分讨论/决定/实现/验证/否决，并建立七份现行文档。见[现行入口](../current/README.md)。

## 制作公开课时，事实与表达的界线

可以讲“我们先相信A，用户体验提出反证，最后改成B”；不能凭记录虚构“那天我彻夜崩溃”“损失了多少收入”“朋友已经普遍认可”。个人动机、情绪、关键对话的完整上下文由本人补充。

不建议把437作为“失败次数”放大字封面。更准确的表述是：**从165份资料中，追出了35类反复、437条相关变更记录；最值得讲的是那些不得不承认第一次判断错了的时刻。**

本轮核验范围：资料盘点、源段落定位、主题去重、现行状态对照和附件链接检查；没有重跑产品测试、没有构建安装、没有修改软件或重新验收历史版本。本文引用的历史测试必须连同样本、版本和局限一起表达。
