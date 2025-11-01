WITH acs_admissions AS (
    SELECT d.hadm_id, d.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE LOWER(di.long_title) LIKE '%acute coronary syndrome%'
       OR LOWER(di.long_title) LIKE '%myocardial infarction%'
       OR LOWER(di.long_title) LIKE '%unstable angina%'
       OR LOWER(di.long_title) LIKE '%stemi%'
       OR LOWER(di.long_title) LIKE '%nstemi%'
),
troponin_first AS (
    SELECT 
        l.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
        ON l.itemid = di.itemid
    WHERE LOWER(di.label) LIKE '%troponin i%'
)
SELECT 
    COUNT(DISTINCT p.subject_id) AS patient_count,
    COUNT(a.hadm_id) AS admission_count,
    AVG(t.valuenum) AS mean_troponin,
    STDDEV(t.valuenum) AS std_troponin,
    MIN(t.valuenum) AS min_troponin,
    MAX(t.valuenum) AS max_troponin
FROM acs_admissions a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
JOIN troponin_first t 
    ON a.hadm_id = t.hadm_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 68 AND 78
  AND t.rn = 1
  AND t.valuenum > 0.04;