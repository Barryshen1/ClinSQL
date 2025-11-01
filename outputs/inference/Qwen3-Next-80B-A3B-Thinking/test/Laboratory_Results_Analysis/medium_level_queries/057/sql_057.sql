WITH acs_admissions AS (
    SELECT a.hadm_id, a.subject_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE p.gender = 'M'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
      AND (LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
           OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
           OR LOWER(dd.long_title) LIKE '%unstable angina%')
),
first_troponin AS (
    SELECT 
        a.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) AS rn
    FROM acs_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
    WHERE l.itemid = 50911
      AND l.valuenum IS NOT NULL
)
SELECT 
    CASE 
        WHEN valuenum <= 0.04 THEN 'normal'
        WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'borderline'
        WHEN valuenum > 0.1 THEN 'elevated'
    END AS troponin_category,
    COUNT(*) AS count
FROM first_troponin
WHERE rn = 1
GROUP BY troponin_category;