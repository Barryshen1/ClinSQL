WITH sepsis_admissions AS (
    SELECT DISTINCT
        d.subject_id,
        d.hadm_id,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON d.subject_id = p.subject_id
    WHERE d.icd_code IN ('A40', 'A41', 'R65')  -- ICD-10 codes for sepsis
        AND d.icd_version = 10
        AND p.gender = 'M'  -- male patients
),
platelet_labs AS (
    SELECT
        l.subject_id,
        l.hadm_id,
        l.valuenum AS platelet_count,
        ROW_NUMBER() OVER (
            PARTITION BY l.hadm_id
            ORDER BY l.charttime
        ) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN sepsis_admissions s
        ON l.subject_id = s.subject_id
        AND l.hadm_id = s.hadm_id
    WHERE l.itemid IN (51265, 52337)  -- platelet count itemids (PLT)
        AND l.valuenum IS NOT NULL  -- ensure we have a numeric value
        AND l.charttime BETWEEN s.admittime AND TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR)
)
SELECT
    STDDEV(platelet_count) AS platelet_stddev
FROM platelet_labs
WHERE rn = 1;  -- only the first platelet count within 24 hours of admission;