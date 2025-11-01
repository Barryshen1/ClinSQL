SELECT STDDEV_SAMP(peak_potassium) AS stddev_peak_potassium
FROM (
    SELECT ce.stay_id, MAX(ce.valuenum) AS peak_potassium
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON p.subject_id = icu.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON icu.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE p.anchor_age = 56
        AND p.gender = 'M'
        AND LOWER(di.label) LIKE '%potassium%'
        AND ce.valuenum IS NOT NULL
        AND LOWER(ce.valueuom) = 'meq/l'
    GROUP BY ce.stay_id
) AS stay_peak_potassium;