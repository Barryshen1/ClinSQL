WITH sepsis_admissions AS (
    SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
    WHERE p.gender = 'M'
    AND (LOWER(d_icd.long_title) LIKE '%sepsis%' OR LOWER(d_icd.long_title) LIKE '%septic%')
),
platelet_first AS (
    SELECT 
        s.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY l.charttime) AS rn
    FROM sepsis_admissions s
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON s.hadm_id = l.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
    WHERE (LOWER(di.label) LIKE '%platelet%' OR LOWER(di.label) = 'plt')
    AND l.charttime BETWEEN s.admittime AND s.dischtime
    AND l.valuenum IS NOT NULL
)
SELECT STDDEV(valuenum) AS platelet_count_sd
FROM platelet_first
WHERE rn = 1;