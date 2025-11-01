WITH cohort AS (
    SELECT DISTINCT 
        p.subject_id, 
        p.anchor_age, 
        p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 78 AND 88
),
pacemaker_codes AS (
    SELECT 
        icd_code, 
        icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE 
        LOWER(long_title) LIKE '%pacemaker%' 
        OR LOWER(long_title) LIKE '%defibrillator%' 
        OR LOWER(long_title) LIKE '%icd%'
),
patient_procedure_counts AS (
    SELECT 
        c.subject_id,
        COUNT(DISTINCT 
            IF(pc.icd_code IS NOT NULL, 
               CONCAT(proc.icd_code, '_', CAST(proc.icd_version AS STRING)), 
               NULL)
        ) AS distinct_procedure_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
        ON c.subject_id = proc.subject_id
        AND c.anchor_age + (EXTRACT(YEAR FROM proc.chartdate) - c.anchor_year) BETWEEN 78 AND 88
    LEFT JOIN pacemaker_codes pc 
        ON proc.icd_code = pc.icd_code 
        AND proc.icd_version = pc.icd_version
    GROUP BY c.subject_id
)
SELECT 
    APPROX_QUANTILES(distinct_procedure_count, 4)[OFFSET(1)] AS percentile_25
FROM patient_procedure_counts;