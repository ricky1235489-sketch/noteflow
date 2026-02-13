class NoteFlowError(Exception):
    def __init__(self, message: str, status_code: int = 400):
        self.message = message
        self.status_code = status_code
        super().__init__(self.message)


class FileValidationError(NoteFlowError):
    def __init__(self, message: str):
        super().__init__(message, status_code=400)


class RateLimitExceeded(NoteFlowError):
    def __init__(self, message: str = "已達本月轉換上限"):
        super().__init__(message, status_code=429)


class TranscriptionNotFound(NoteFlowError):
    def __init__(self, transcription_id: str):
        super().__init__(
            f"找不到轉譜記錄: {transcription_id}", status_code=404
        )


class TranscriptionFailed(NoteFlowError):
    def __init__(self, message: str = "轉譜處理失敗"):
        super().__init__(message, status_code=500)
