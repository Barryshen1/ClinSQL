WITH eligible_admissions AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE d.seq_num = 1
      AND p.gender = 'F'
      AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 58 AND 68
      AND (di.long_title LIKE '%chest pain%' 
           OR di.long_title LIKE '%acute myocardial infarction%' 
           OR di.long_title LIKE '%AMI%')
),
first_troponin AS (
    SELECT 
        l.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
    WHERE di.label LIKE '%Troponin T%'
)
SELECT 
    AVG(valuenum) AS mean,
    STDDEV(valuenum) AS std,
    MIN(valuenum) AS min,
    MAX(valuenum) AS max
FROM first_troponin ft
JOIN eligible_admissions ea ON ft.hadm_id = ea.hadm_id
WHERE ft.rn = 1 AND ft.valuenum > 0.01;