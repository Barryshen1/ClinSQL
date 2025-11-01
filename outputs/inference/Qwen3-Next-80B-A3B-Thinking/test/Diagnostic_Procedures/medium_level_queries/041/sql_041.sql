WITH imaging AS (
    SELECT hadm_id, COUNT(*) AS num_procedures
    FROM (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
        WHERE LOWER(short_description) LIKE '%ct%'
           OR LOWER(short_description) LIKE '%x-ray%'
           OR LOWER(short_description) LIKE '%xray%'
           OR LOWER(short_description) LIKE '%radiograph%'
           OR LOWER(short_description) LIKE '%radiology%'
        UNION ALL
        SELECT p.hadm_id
        FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON p.itemid = d.itemid
        WHERE LOWER(d.label) LIKE '%ct%'
           OR LOWER(d.label) LIKE '%x-ray%'
           OR LOWER(d.label) LIKE '%xray%'
           OR LOWER(d.label) LIKE '%radiograph%'
           OR LOWER(d.label) LIKE '%radiology%'
    ) AS combined
    GROUP BY hadm_id
),
acute_pancreatitis_admissions AS (
    SELECT 
        a.hadm_id,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
        MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary,
        MAX(CASE WHEN di.seq_num > 1 THEN 1 ELSE 0 END) AS is_secondary
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 51 AND 61
      AND LOWER(d.long_title) LIKE '%acute pancreatitis%'
    GROUP BY a.hadm_id, a.admittime, a.dischtime
)
SELECT 
    CASE 
        WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    CASE 
        WHEN is_primary = 1 THEN 'primary'
        WHEN is_secondary = 1 THEN 'secondary'
    END AS diagnosis_type,
    COUNT(*) AS patient_count,
    AVG(imaging.num_procedures) AS mean_procedures
FROM acute_pancreatitis_admissions a
LEFT JOIN imaging ON a.hadm_id = imaging.hadm_id
WHERE los BETWEEN 1 AND 7
GROUP BY los_group, diagnosis_type;