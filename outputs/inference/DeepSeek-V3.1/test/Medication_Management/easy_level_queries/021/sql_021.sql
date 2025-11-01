WITH statin_prescriptions AS (
    SELECT
        p.subject_id,
        p.drug,
        p.dose_val_rx,
        p.dose_unit_rx,
        DATETIME_DIFF(p.stoptime, p.starttime, HOUR) / 24.0 AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON p.subject_id = pt.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.hadm_id = adm.hadm_id
    WHERE
        pt.anchor_age BETWEEN 75 AND 85
        AND pt.gender = 'F'
        AND LOWER(p.drug) LIKE '%atorvastatin%'
        AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
        AND p.stoptime IS NOT NULL
        AND p.starttime < p.stoptime
)
SELECT
    APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS q25_days,
    APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_days,
    APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS q75_days
FROM statin_prescriptions;