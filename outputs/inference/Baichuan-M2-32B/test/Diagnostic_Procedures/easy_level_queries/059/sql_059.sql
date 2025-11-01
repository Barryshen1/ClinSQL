WITH cardiac_procedures AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE long_title LIKE '%cardiac%' OR long_title LIKE '%heart%'
),
patient_hospitalizations AS (
    SELECT 
        p.subject_id,
        a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 76 AND 86
),
filtered_procedures AS (
    SELECT 
        p.subject_id, 
        p.hadm_id, 
        p.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN cardiac_procedures c 
        ON p.icd_code = c.icd_code
),
procedures_per_hospitalization AS (
    SELECT 
        ph.subject_id,
        ph.hadm_id,
        COUNT(DISTINCT fp.icd_code) AS distinct_cardiac_procedures
    FROM patient_hospitalizations ph
    LEFT JOIN filtered_procedures fp
        ON ph.subject_id = fp.subject_id
        AND ph.hadm_id = fp.hadm_id
    GROUP BY ph.subject_id, ph.hadm_id
)
SELECT 
    APPROX_QUANTILES(distinct_cardiac_procedures, 100)[OFFSET(75)] - 
    APPROX_QUANTILES(distinct_cardiac_procedures, 100)[OFFSET(25)] AS iqr
FROM procedures_per_hospitalization;