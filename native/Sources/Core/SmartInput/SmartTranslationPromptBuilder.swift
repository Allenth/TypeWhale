import Foundation

enum SmartTranslationPromptBuilder {
    static func prompt(
        source: String,
        direction: SmartTranslationDirection,
        context: SmartInputContext,
        triggeredBy: String
    ) -> String {
        if triggeredBy == "screenshot_translation" {
            return """
            你是 TypeWhale 的截图 OCR 翻译助手。

            翻译方向：\(direction.displayName)
            任务：把截图 OCR 识别出的英文界面文字、网页文字、按钮文案、菜单项、短标签和普通句子逐行翻译成自然中文。

            硬规则：
            - 这是截图 OCR 文本，不是语音转写；不要按“语音翻译”理解。
            - 每一行只要包含可读英文，就必须翻译成中文；短词、按钮、菜单、标题、状态词也必须翻译。
            - 不要因为英文很短、像产品界面、像专有名词或像标签就原样照抄。
            - 专有名词、产品名、品牌名、代码、API、文件名、变量名、版本号可以保留英文；但其周围的普通英文必须翻译。
            - 无法确定上下文时，给出最可能的中文译法，不要输出原英文作为逃避。
            - 只输出译文，不要解释、不要 Markdown、不要额外标题。

            \(direction.toneInstruction)
            \(translationLayoutInstruction(triggeredBy: triggeredBy))

            目标应用：\(context.targetAppName ?? "截图")

            OCR 行文本：
            \(source)
            """
        }

        return """
        你是 TypeWhale 的语音翻译助手。

        翻译方向：\(direction.displayName)
        任务：\(direction.targetLanguageInstruction)

        规则：
        - 只输出译文，不要输出原文、解释、标签或 Markdown。
        - 保留人名、产品名、模型名、代码、API、库名等必要专有名词。
        - 修正明显的语音识别错误，但不要新增原文没有的信息。
        - 语气自然，适合直接粘贴到当前输入框。

        \(direction.toneInstruction)
        \(translationLayoutInstruction(triggeredBy: triggeredBy))

        目标应用：\(context.targetAppName ?? "未知")

        原始语音文本：
        \(source)
        """
    }

    private static func translationLayoutInstruction(triggeredBy: String) -> String {
        guard triggeredBy == "screenshot_translation" else { return "" }
        return """

        截图翻译版面规则：
        - 原始文本来自 OCR 行，每行格式为 [[TW_LINE_n]] 原文。
        - 必须逐行返回同样的 [[TW_LINE_n]]，并在其后输出该行对应的中文译文。
        - 不要丢失、合并、重排或改写 line id。
        - 即使某一行只有一个英文单词、按钮文案或菜单项，也必须返回该 line id 和中文译文。
        - 如果某行确实只有品牌名、代码、数字或无法翻译的专有名词，仍返回 line id，并保留该专有名词。
        - 不要额外添加标题、列表符号、解释或没有 line id 的文本。
        - 输出示例：[[TW_LINE_1]] 这是第一行译文
        """
    }
}
