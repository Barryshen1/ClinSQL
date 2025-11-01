WITH patient_admissions AS (
    SELECT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 80 AND 90
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
            ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
          WHERE d.hadm_id = a.hadm_id
            AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
      )
),
ultrasound_counts AS (
    SELECT hadm_id, COUNT(*) AS total_ultrasounds
    FROM (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
          ON p.itemid = d.itemid
        WHERE d.label LIKE '%ultrasound%'
        UNION ALL
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
        JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
          ON h.hcpcs_cd = d.code
        WHERE d.long_description LIKE '%ultrasound%'
    ) AS combined
    GROUP BY hadm_id
),
los_data AS (
    SELECT 
        pa.hadm_id,
        DATE_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
        COALESCE(uc.total_ultrasounds, 0) AS total_ultrasounds
    FROM patient_admissions pa
    LEFT JOIN ultrasound_counts uc ON pa.hadm_id = uc.hadm_id
)
SELECT 
    CASE 
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS stay_group,
    AVG(total_ultrasounds) AS mean_ultrasounds,
    MIN(total_ultrasounds) AS min_ultrasounds,
    MAX(total_ultrasounds) AS max_ultrasounds
FROM los_data
WHERE los_days BETWEEN 1 AND 7
GROUP BY stay_group;