WITH hfnc_patients AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        ie.stay_id,
        ie.intime,
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 88 AND 98
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
            WHERE ce.itemid = 226732 -- High Flow Nasal Cannula
                AND ce.stay_id = ie.stay_id
        )
),
gcs_records AS (
    SELECT 
        hp.stay_id,
        ce.valuenum AS gcs_total
    FROM hfnc_patients hp
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON hp.stay_id = ce.stay_id
    WHERE ce.itemid = 198 -- GCS total
        AND ce.valuenum IS NOT NULL
        AND DATETIME_DIFF(ce.charttime, hp.intime, HOUR) >= 24 -- ICU day 2 or later
)
SELECT 
    APPROX_QUANTILES(gcs_total, 2)[OFFSET(1)] AS median_gcs_total
FROM gcs_records;