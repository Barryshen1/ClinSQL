WITH atorva_prescriptions AS (
    SELECT
        p.subject_id,
        pr.hadm_id,
        pr.starttime,
        pr.stoptime,
        DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pr.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON pr.hadm_id = a.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 60 AND 70
        AND LOWER(pr.drug) LIKE '%atorvastatin%'
        AND pr.dose_val_rx IN ('40', '80')  -- Changed to string literals
        AND pr.dose_unit_rx = 'mg'
        AND pr.stoptime IS NOT NULL
        AND pr.starttime IS NOT NULL
)
SELECT
    APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS q25,
    APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS q75,
    APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr
FROM atorva_prescriptions;