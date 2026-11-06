<?php

namespace App\Enums;

enum VoiceNoteStatus: string
{
    case Processing = 'processing';
    case Done = 'done';
    case Failed = 'failed';
}
