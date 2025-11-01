WITH base AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
),
filtered_base AS (
    SELECT hadm_id
    FROM base
    WHERE age_at_admission BETWEEN 52 AND 62
),
valve_procedures AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE 
        REGEXP_CONTAINS(LOWER(long_title), r'(valve|valvuloplasty).*(repair|replacement|plasty)') OR
        REGEXP_CONTAINS(LOWER(long_title), r'(repair|replacement|plasty).*(valve|valvuloplasty)')
),
counts AS (
    SELECT 
        fb.hadm_id,
        COUNT(DISTINCT CONCAT(p.icd_code, '_', p.icd_version)) AS valve_proc_count
    FROM filtered_base fb
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        ON fb.hadm_id = p.hadm_id
    LEFT JOIN valve_procedures v
        ON p.icd_code = v.icd_code AND p.icd_version = v.icd_version
    GROUP BY fb.hadm_id
)
SELECT 
    APPROX_QUANTILES(valve_proc_count, 100)[OFFSET(25)] AS q25,
    APPROX_QUANTILES(valve_proc_count, 100)[OFFSET(75)] AS q75,
    APPROX_QUANTILES(valve_proc_count, 100)[OFFSET(75)] - APPROX_QUANTILES(valve_proc_count, 100)[OFFSET(25)] AS iqr
FROM counts;