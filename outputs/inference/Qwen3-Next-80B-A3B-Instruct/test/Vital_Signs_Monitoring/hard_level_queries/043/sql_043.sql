SELECT itemid, label FROM physionet-data.mimiciv_3_1_icu.d_items 
WHERE LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%heart rate%';