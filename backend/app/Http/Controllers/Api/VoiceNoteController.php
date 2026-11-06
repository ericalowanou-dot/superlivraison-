<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Enums\VoiceNoteStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\VoiceNoteResource;
use App\Jobs\TranscribeVoiceNote;
use App\Models\VoiceNote;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class VoiceNoteController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        abort_unless($request->user()->role === Role::Restaurant, 403);

        $data = $request->validate([
            'audio' => ['required', 'file', 'extensions:m4a,aac,mp3,ogg,opus,wav', 'mimetypes:audio/mp4,audio/x-m4a,audio/aac,audio/mpeg,audio/ogg,audio/opus,audio/wav,audio/x-wav,video/mp4', 'max:'.config('superlivraison.voice_max_kb')],
            'duration_seconds' => ['nullable', 'integer', 'min:1', 'max:600'],
        ]);

        $path = $request->file('audio')->store('voice/'.$request->user()->id, config('superlivraison.media_disk'));

        $note = $request->user()->voiceNotes()->create([
            'path' => $path,
            'duration_seconds' => $data['duration_seconds'] ?? null,
            'status' => VoiceNoteStatus::Processing,
        ]);

        TranscribeVoiceNote::dispatch($note);

        return (new VoiceNoteResource($note->refresh()))->response()->setStatusCode(201);
    }

    /** L'application interroge cette adresse jusqu'à ce que la retranscription soit prête. */
    public function show(Request $request, VoiceNote $voiceNote): VoiceNoteResource
    {
        abort_unless($voiceNote->user_id === $request->user()->id, 404);

        return new VoiceNoteResource($voiceNote);
    }
}
