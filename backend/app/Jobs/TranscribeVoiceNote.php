<?php

namespace App\Jobs;

use App\Contracts\Transcriber;
use App\Enums\VoiceNoteStatus;
use App\Models\VoiceNote;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Throwable;

class TranscribeVoiceNote implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public int $backoff = 15;

    public function __construct(public VoiceNote $note) {}

    public function handle(Transcriber $transcriber): void
    {
        $language = $this->note->user->language_code ?? 'fr';

        $this->note->forceFill([
            'transcript' => $transcriber->transcribe($this->note->path, $language),
            'status' => VoiceNoteStatus::Done,
        ])->save();
    }

    /** Sans retranscription, le restaurant écrit lui-même et l'opérateur garde le vocal. */
    public function failed(?Throwable $e): void
    {
        $this->note->forceFill(['status' => VoiceNoteStatus::Failed])->save();
    }
}
