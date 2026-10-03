import OpenNoTypeCore

enum DictationExpressionExamples {
    static var source: String {
        L(
            "민서에게 초안을 내일 오후 3시까지 보내 주세요. OpenNoType으로 녹음한 말을 읽기 쉽게 정리하고 싶어요, 음, 읽기 쉽게 정리하고 싶어요. 같은 말이 반복돼서 내용을 따라가기 어렵거든요. 숫자 12와 18은 바꾸지 말아 주세요. 승인 전에는 공개하지 말아 주세요.",
            "Please send the draft to Minseo by 3 PM tomorrow. I want to use OpenNoType to make my recorded speech easier to read, um, easier to read. The repeated phrases make it hard to follow. Please do not change the numbers 12 and 18. Please do not publish it before approval."
        )
    }

    static func result(for style: DictationExpressionStyle) -> String {
        switch style {
        case .faithful:
            L(
                "민서에게 초안을 내일 오후 3시까지 보내 주세요. OpenNoType으로 녹음한 말을 읽기 쉽게 정리하고 싶어요. 같은 말이 반복돼서 내용을 따라가기 어렵거든요. 숫자 12와 18은 바꾸지 말아 주세요. 승인 전에는 공개하지 말아 주세요.",
                "Please send the draft to Minseo by 3 PM tomorrow. I want to use OpenNoType to make my recorded speech easier to read. The repeated phrases make it hard to follow. Please do not change the numbers 12 and 18. Please do not publish it before approval."
            )
        case .concise:
            L(
                "민서에게 초안을 내일 오후 3시까지 보내 주세요. 반복 때문에 따라가기 어려운 녹음을 OpenNoType으로 읽기 쉽게 정리하고 싶어요. 숫자 12와 18은 바꾸지 말고, 승인 전에는 공개하지 말아 주세요.",
                "Please send the draft to Minseo by 3 PM tomorrow. I want to use OpenNoType to improve my recorded speech's readability because repeated phrases make it hard to follow. Please keep the numbers 12 and 18 unchanged and do not publish it before approval."
            )
        case .summary:
            L(
                "OpenNoType으로 반복 때문에 따라가기 어려운 녹음을 읽기 쉽게 정리하고 싶어요.\n\n• 초안을 민서에게 내일 오후 3시까지 보내 주세요.\n• 숫자 12와 18은 바꾸지 말아 주세요.\n• 승인 전에는 공개하지 말아 주세요.",
                "I want to use OpenNoType to improve my recorded speech's readability because repeated phrases make it hard to follow.\n\n• Please send the draft to Minseo by 3 PM tomorrow.\n• Please keep the numbers 12 and 18 unchanged.\n• Please do not publish it before approval."
            )
        case .clear:
            L(
                "같은 말이 반복돼서 녹음 내용을 따라가기 어려워요. 그래서 OpenNoType으로 녹음한 말을 읽기 쉽게 정리하고 싶어요. 민서에게 초안을 내일 오후 3시까지 보내 주세요. 숫자 12와 18은 바꾸지 말아 주세요. 승인 전에는 공개하지 말아 주세요.",
                "Repeated phrases make my recorded speech hard to follow. That is why I want to use OpenNoType to make it easier to read. Please send the draft to Minseo by 3 PM tomorrow. Please do not change the numbers 12 and 18. Please do not publish it before approval."
            )
        case .expanded:
            L(
                "녹음한 말에는 같은 표현이 반복돼요. 이렇게 같은 말이 반복되니 내용을 따라가기가 어려워요. 그래서 OpenNoType을 사용해 녹음한 말을 읽기 쉬운 문장으로 정리하고 싶어요. 초안은 내일 오후 3시까지 민서에게 보내 주세요. 숫자 12와 18은 원래 값에서 바꾸지 말아 주세요. 승인을 받기 전에는 공개하지 말아 주세요.",
                "My recorded speech contains repeated phrases. Those repeated phrases make the content difficult to follow. That is why I want to use OpenNoType to organize my recorded speech into sentences that are easier to read. Please send the draft to Minseo by 3 PM tomorrow. Please leave the numbers 12 and 18 at their original values. Please do not publish it before approval has been given."
            )
        case .creative:
            L(
                "되풀이되는 말 때문에 녹음의 흐름을 따라가기가 어려워요. OpenNoType으로 그 말을 다듬어, 읽기 쉬운 문장으로 만들고 싶어요. 내일 오후 3시까지 민서에게 초안을 보내 주세요. 숫자는 12와 18 그대로, 바꾸지 말아 주세요. 공개는 승인 전까지 하지 말아 주세요.",
                "Repeated phrases make the flow of my recorded speech hard to follow. I want to use OpenNoType to reshape those words into sentences that are easier to read. Please send the draft to Minseo by 3 PM tomorrow. Please leave the numbers as they are: 12 and 18. Please wait for approval before publishing it."
            )
        }
    }
}
