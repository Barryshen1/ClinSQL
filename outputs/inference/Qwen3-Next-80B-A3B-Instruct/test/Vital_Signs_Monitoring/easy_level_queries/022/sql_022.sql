SELECT AVG(max_map_per_stay) AS average_of_maximum_map
FROM (
    SELECT i.stay_id, MAX(ce.valuenum) AS max_map_per_stay
    FROM physionet-data.mimiciv_3_1_icu.icustays i
    INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
        ON i.subject_id = p.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
        ON i.stay_id = ce.stay_id
    INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
        ON ce.itemid = di.itemid
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 48 AND 58
        AND LOWER(di.label) LIKE '%map%'
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 20 AND 200  -- clinically plausible MAP range
    GROUP BY i.stay_id
) AS max_maps_per_stay;