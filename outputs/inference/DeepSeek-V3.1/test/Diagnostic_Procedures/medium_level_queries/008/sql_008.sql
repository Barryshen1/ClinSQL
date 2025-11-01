WITH hhs_patients AS (
    SELECT DISTINCT p.subject_id, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON p.subject_id = di.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 58 AND 68
        AND (
            (dd.icd_version = 10 AND dd.icd_code LIKE 'E11.00%') 
            OR (dd.icd_version = 9 AND dd.icd_code = '250.2')
        )
),
los_groups AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE 
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
            ELSE 'Other'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN hhs_patients hp ON a.subject_id = hp.subject_id
    WHERE DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
proc_counts AS (
    SELECT 
        lg.hadm_id,
        lg.los_group,
        COUNT(pi.icd_code) AS num_rad_ct_procedures
    FROM los_groups lg
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
        ON lg.hadm_id = pi.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
        ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
    WHERE 
        (dp.icd_version = 10 AND dp.icd_code LIKE 'B%') 
        OR (dp.icd_version = 9 AND dp.icd_code BETWEEN '87%' AND '88%')
    GROUP BY lg.hadm_id, lg.los_group
)
SELECT 
    los_group,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(num_rad_ct_procedures) AS mean_procedures_per_admission
FROM (
    SELECT 
        lg.subject_id,
        lg.hadm_id,
        lg.los_group,
        COALESCE(pc.num_rad_ct_procedures, 0) AS num_rad_ct_procedures
    FROM los_groups lg
    LEFT JOIN proc_counts pc ON lg.hadm_id = pc.hadm_id
)
GROUP BY los_group
ORDER BY los_group;