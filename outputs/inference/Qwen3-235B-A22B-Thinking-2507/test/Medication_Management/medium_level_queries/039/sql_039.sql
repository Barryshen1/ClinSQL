WITH patients_cohort AS (
    SELECT 
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
),
cohort_with_conditions AS (
    SELECT c.hadm_id, c.admittime, c.dischtime
    FROM patients_cohort c
    WHERE 
        EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = c.hadm_id
                AND d.icd_version = 10
                AND d.icd_code LIKE 'E11%'
        )
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = c.hadm_id
                AND d.icd_version = 10
                AND d.icd_code LIKE 'I50%'
        )
),
glp1_orders AS (
    SELECT 
        hadm_id, 
        starttime, 
        stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE 
        (LOWER(drug) LIKE '%exenatide%' 
         OR LOWER(drug) LIKE '%liraglutide%'
         OR LOWER(drug) LIKE '%dulaglutide%'
         OR LOWER(drug) LIKE '%semaglutide%'
         OR LOWER(drug) LIKE '%byetta%'
         OR LOWER(drug) LIKE '%bydureon%'
         OR LOWER(drug) LIKE '%victoza%'
         OR LOWER(drug) LIKE '%trulicity%'
         OR LOWER(drug) LIKE '%ozempic%'
        )
        AND (route IS NOT NULL AND 
             (LOWER(route) LIKE '%subcut%' 
              OR LOWER(route) = 'sc' 
              OR LOWER(route) = 'sq' 
              OR LOWER(route) = 'sub q' 
              OR LOWER(route) = 'sub-q'
             )
        )
),
cohort_flags AS (
    SELECT 
        c.hadm_id,
        -- first 24h flag
        CASE WHEN EXISTS (
            SELECT 1 
            FROM glp1_orders g 
            WHERE g.hadm_id = c.hadm_id
                AND g.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
                AND (g.stoptime IS NULL OR g.stoptime > c.admittime)
        ) THEN 1 ELSE 0 END AS first24h_flag,
        -- final 48h flag
        CASE WHEN EXISTS (
            SELECT 1 
            FROM glp1_orders g 
            WHERE g.hadm_id = c.hadm_id
                AND g.starttime < c.dischtime
                AND (g.stoptime IS NULL OR g.stoptime > GREATEST(c.admittime, TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)))
        ) THEN 1 ELSE 0 END AS final48h_flag
    FROM cohort_with_conditions c
),
counts AS (
    SELECT 
        COUNT(*) AS total,
        SUM(first24h_flag) AS count_first24h,
        SUM(final48h_flag) AS count_final48h
    FROM cohort_flags
)
SELECT 
    SAFE_DIVIDE(count_first24h * 100.0, total) AS prevalence_first24h,
    SAFE_DIVIDE(count_final48h * 100.0, total) AS prevalence_final48h,
    SAFE_DIVIDE(count_final48h * 100.0, total) - SAFE_DIVIDE(count_first24h * 100.0, total) AS absolute_change,
    CASE 
        WHEN count_first24h = 0 THEN NULL 
        ELSE SAFE_DIVIDE((count_final48h - count_first24h) * 100.0, count_first24h)
    END AS relative_change_percent
FROM counts;