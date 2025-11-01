WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.anchor_age BETWEEN 39 AND 49
        AND p.gender = 'F'
        AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
                ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
            WHERE d.long_title LIKE '%Type 2 diabetes%'
        )
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
                ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
            WHERE d.long_title LIKE '%Heart failure%'
        )
),

insulin_orders AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        -- Check for basal insulin in first 72h
        MAX(CASE WHEN LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%NPH%' 
                 AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
            THEN 1 ELSE 0 END) AS basal_first72,
        -- Check for basal insulin in final 48h
        MAX(CASE WHEN LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%NPH%' 
                 AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
            THEN 1 ELSE 0 END) AS basal_final48,

        -- Check for bolus insulin in first 72h
        MAX(CASE WHEN (LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%regular%' OR LOWER(p.drug) LIKE '%humalog%' OR LOWER(p.drug) LIKE '%novolog%')
                 AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
            THEN 1 ELSE 0 END) AS bolus_first72,
        -- Check for bolus insulin in final 48h
        MAX(CASE WHEN (LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%regular%' OR LOWER(p.drug) LIKE '%humalog%' OR LOWER(p.drug) LIKE '%novolog%')
                 AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
            THEN 1 ELSE 0 END) AS bolus_final48,

        -- Check for sliding scale in first 72h
        MAX(CASE WHEN LOWER(p.drug) LIKE '%sliding%' OR LOWER(p.drug) LIKE '%scale%'
                 AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
            THEN 1 ELSE 0 END) AS sliding_first72,
        -- Check for sliding scale in final 48h
        MAX(CASE WHEN LOWER(p.drug) LIKE '%sliding%' OR LOWER(p.drug) LIKE '%scale%'
                 AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
            THEN 1 ELSE 0 END) AS sliding_final48

    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
    GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)

SELECT 
    'Basal' AS insulin_type,
    ROUND(100 * AVG(basal_first72), 2) AS pct_first72,
    ROUND(100 * AVG(basal_final48), 2) AS pct_final48,
    ROUND(100 * (AVG(basal_first72) - AVG(basal_final48)), 2) AS absolute_diff
FROM insulin_orders

UNION ALL

SELECT 
    'Bolus' AS insulin_type,
    ROUND(100 * AVG(bolus_first72), 2) AS pct_first72,
    ROUND(100 * AVG(bolus_final48), 2) AS pct_final48,
    ROUND(100 * (AVG(bolus_first72) - AVG(bolus_final48)), 2) AS absolute_diff
FROM insulin_orders

UNION ALL

SELECT 
    'Basal-Bolus' AS insulin_type,
    ROUND(100 * AVG(CASE WHEN basal_first72 = 1 AND bolus_first72 = 1 THEN 1 ELSE 0 END), 2) AS pct_first72,
    ROUND(100 * AVG(CASE WHEN basal_final48 = 1 AND bolus_final48 = 1 THEN 1 ELSE 0 END), 2) AS pct_final48,
    ROUND(100 * (AVG(CASE WHEN basal_first72 = 1 AND bolus_first72 = 1 THEN 1 ELSE 0 END) - 
                 AVG(CASE WHEN basal_final48 = 1 AND bolus_final48 = 1 THEN 1 ELSE 0 END)), 2) AS absolute_diff
FROM insulin_orders

UNION ALL

SELECT 
    'Sliding-Scale' AS insulin_type,
    ROUND(100 * AVG(sliding_first72), 2) AS pct_first72,
    ROUND(100 * AVG(sliding_final48), 2) AS pct_final48,
    ROUND(100 * (AVG(sliding_first72) - AVG(sliding_final48)), 2) AS absolute_diff
FROM insulin_orders;