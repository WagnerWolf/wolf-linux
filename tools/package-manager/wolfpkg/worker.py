from PySide6.QtCore import QThread, Signal
from .backend import check_all_updates
from .postcheck import run_post_update_checks
from .search_service import search_parallel

class CheckWorker(QThread):
    done = Signal(object, object)
    def run(self):
        results, errors = check_all_updates()
        self.done.emit(results, errors)

class SearchWorker(QThread):
    done = Signal(object, object)
    progress = Signal(str, int, int, bool)

    def __init__(self, query, scope, parent=None):
        super().__init__(parent)
        self.query, self.scope = query, scope

    def run(self):
        try:
            results, errors = search_parallel(
                self.query, self.scope,
                on_progress=lambda source, completed, total, cached:
                    self.progress.emit(source, completed, total, cached))
        except Exception as exc:
            results, errors = [], {'Pesquisa': str(exc)}
        self.done.emit(results, errors)


class PostUpdateWorker(QThread):
    """Read-only, potentially slow system verification outside the GUI thread."""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.report = None

    def run(self):
        try:
            self.report = run_post_update_checks()
        except Exception as exc:
            from .postcheck import PostUpdateReport
            self.report = PostUpdateReport((f'Erro ao verificar o boot/DKMS: {exc}',), (), ())
