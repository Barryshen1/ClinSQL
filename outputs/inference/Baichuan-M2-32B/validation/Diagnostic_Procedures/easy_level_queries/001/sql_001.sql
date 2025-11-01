WITH eligible_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
),
filtered_patients AS (
    SELECT *
    FROM eligible_patients
    WHERE age_at_admission BETWEEN 63 AND 73
),
cardiac_procedures_per_hadm AS (
    SELECT 
        f.hadm_id,
        COUNT(DISTINCT p.icd_code) AS distinct_cardiac_procedures
    FROM filtered_patients f
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        ON f.hadm_id = p.hadm_id
        AND f.subject_id = p.subject_id
        AND p.icd_version = 9
        AND CAST(SUBSTR(p.icd_code, 1, 3) AS INT64) IN (36, 37, 38, 39)
    GROUP BY f.hadm_id
)
SELECT 
    APPROX_QUANTILES(distinct_cardiac_procedures, 100)[OFFSET(75)] AS p75
FROM cardiac_procedures_per_hadm;