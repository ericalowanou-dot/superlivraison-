<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Country;
use App\Models\Language;
use Illuminate\Http\JsonResponse;

class ReferenceController extends Controller
{
    /** Pays, villes et langues viennent de la base : on en ajoute sans mettre à jour l'application (T4). */
    public function __invoke(): JsonResponse
    {
        return response()->json([
            'languages' => Language::where('is_active', true)->orderBy('name')->get(['code', 'name']),
            'countries' => Country::where('is_active', true)
                ->with(['cities' => fn ($q) => $q->where('is_active', true)->orderBy('name')->select('id', 'country_id', 'name')])
                ->orderBy('name')
                ->get(['id', 'name', 'code', 'dial_code', 'currency']),
        ]);
    }
}
