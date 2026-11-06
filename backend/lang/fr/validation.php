<?php

return [
    'required' => 'Ce champ est obligatoire.',
    'required_with' => 'Ce champ est obligatoire.',
    'string' => 'Ce champ doit être un texte.',
    'integer' => 'Ce champ doit être un nombre entier.',
    'numeric' => 'Ce champ doit être un nombre.',
    'uuid' => 'Cet identifiant est invalide.',
    'file' => 'Ce fichier est invalide.',
    'exists' => 'Cette valeur est invalide.',
    'in' => 'Cette valeur est invalide.',
    'enum' => 'Cette valeur est invalide.',
    'mimetypes' => 'Ce format de fichier n\'est pas accepté.',
    'extensions' => 'Ce format de fichier n\'est pas accepté.',
    'between' => ['numeric' => 'La valeur doit être comprise entre :min et :max.'],
    'min' => [
        'string' => 'Ce texte doit contenir au moins :min caractères.',
        'numeric' => 'La valeur doit être au moins :min.',
    ],
    'max' => [
        'string' => 'Ce texte ne doit pas dépasser :max caractères.',
        'numeric' => 'La valeur ne doit pas dépasser :max.',
        'file' => 'Ce fichier est trop volumineux.',
    ],
];
