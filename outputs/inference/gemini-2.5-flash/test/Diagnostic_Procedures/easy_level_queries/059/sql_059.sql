WITH patient_admissions AS (
    SELECT
        pa.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 76 AND 86
),
cardiac_procedures_per_hadm AS (
    SELECT
        pa.subject_id,
        pa.hadm_id,
        COUNT(DISTINCT pr.icd_code) AS num_distinct_cardiac_procedures
    FROM
        patient_admissions AS pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
        ON pa.subject_id = pr.subject_id AND pa.hadm_id = pr.hadm_id
    WHERE
        -- Filter for cardiac procedures based on ICD codes
        -- ICD-9-CM: Procedures on the Circulatory System, specifically Heart and Great Vessels
        -- ICD-10-PCS: Medical and Surgical, Body System 'Heart and Great Vessels'
        (
            (pr.icd_version = 9 AND (pr.icd_code LIKE '35%' OR pr.icd_code LIKE '36%' OR pr.icd_code LIKE '37%'))
            OR
            (pr.icd_version = 10 AND pr.icd_code LIKE '02%')
        )
    GROUP BY
        pa.subject_id,
        pa.hadm_id
)
SELECT
    APPROX_QUANTILES(num_distinct_cardiac_procedures, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(num_distinct_cardiac_procedures, 4)[OFFSET(3)] AS q3,
    (APPROX_QUANTILES(num_distinct_cardiac_procedures, 4)[OFFSET(3)] - APPROX_QUANTILES(num_distinct_cardiac_procedures, 4)[OFFSET(1)]) AS iqr
FROM
    cardiac_procedures_per_hadm;