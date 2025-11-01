SELECT AVG(max_map) AS average_of_maximum_map
FROM (
    SELECT ce.stay_id, MAX(ce.valuenum) AS max_map
    FROM physionet-data.mimiciv_3_1_icu.icustays AS icu
    JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
        ON icu.subject_id = pat.subject_id
    JOIN physionet-data.mimiciv_3_1_icu.chartevents AS ce
        ON icu.stay_id = ce.stay_id
    JOIN physionet-data.mimiciv_3_1_icu.d_items AS di
        ON ce.itemid = di.itemid
    WHERE pat.gender = 'M'
      AND pat.anchor_age BETWEEN 48 AND 58
      AND di.label = 'MAP'
      AND ce.valuenum IS NOT NULL
      AND ce.valueuom IS NOT NULL
    GROUP BY ce.stay_id
) AS stay_max_map;