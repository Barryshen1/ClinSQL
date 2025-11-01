WITH PatientCohort AS (
    SELECT DISTINCT
        p.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 86 AND 96
),
AtorvastatinPrescriptions_WithDosage AS (
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pres.starttime,
        pres.stoptime,
        -- Extract numerical dosage from prod_strength, robustly handling 'mg' unit
        -- Modified REGEXP_EXTRACT to use a non-capturing group for the decimal part
        SAFE_CAST(TRIM(REGEXP_EXTRACT(LOWER(pres.prod_strength), r'(\d+(?:\.\d+)?)\s*mg\b')) AS FLOAT64) AS dosage_mg
    FROM
        PatientCohort pc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
        ON pc.subject_id = pres.subject_id
        AND pc.hadm_id = pres.hadm_id
    WHERE
        LOWER(pres.drug) LIKE '%atorvastatin%'
        -- Ensure prod_strength contains 'mg' to correctly extract dosage
        AND LOWER(pres.prod_strength) LIKE '%mg%'
        AND pres.stoptime IS NOT NULL
        AND pres.starttime IS NOT NULL
        AND pres.stoptime >= pres.starttime -- Ensure valid duration
)
SELECT
    MIN(DATE_DIFF(apw.stoptime, apw.starttime, DAY)) AS min_high_intensity_atorvastatin_duration_days
FROM
    AtorvastatinPrescriptions_WithDosage apw
WHERE
    apw.dosage_mg BETWEEN 40 AND 80
;