WITH cardiac_procedures AS (
    SELECT 
        pi.hadm_id,
        pi.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
        ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
    WHERE 
        dip.long_title LIKE '%heart%' OR
        dip.long_title LIKE '%cardiac%' OR
        dip.long_title LIKE '%coronary%' OR
        dip.long_title LIKE '%myocardial%' OR
        dip.long_title LIKE '%valve%' OR
        dip.long_title LIKE '%bypass%'
),
target_hadm AS (
    SELECT 
        a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'M' AND 
        p.anchor_age BETWEEN 76 AND 86
),
counts_per_hadm AS (
    SELECT 
        th.hadm_id,
        COUNT(DISTINCT cp.icd_code) AS num_cardiac_procedures
    FROM target_hadm th
    LEFT JOIN cardiac_procedures cp 
        ON th.hadm_id = cp.hadm_id
    GROUP BY th.hadm_id
)
SELECT 
    PERCENTILE_CONT(num_cardiac_procedures, 0.25) OVER() AS q1,
    PERCENTILE_CONT(num_cardiac_procedures, 0.75) OVER() AS q3,
    PERCENTILE_CONT(num_cardiac_procedures, 0.75) OVER() - PERCENTILE_CONT(num_cardiac_procedures, 0.25) OVER() AS iqr
FROM counts_per_hadm
LIMIT 1;