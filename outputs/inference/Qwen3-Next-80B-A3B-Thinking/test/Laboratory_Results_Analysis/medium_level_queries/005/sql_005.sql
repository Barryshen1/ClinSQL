WITH eligible_admissions AS (
    SELECT 
        p.subject_id, 
        d_icd.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd 
        ON p.subject_id = d_icd.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag 
        ON d_icd.icd_code = d_diag.icd_code 
        AND d_icd.icd_version = d_diag.icd_version
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 35 AND 45
        AND d_icd.seq_num = 1
        AND (d_diag.long_title LIKE '%chest pain%' OR d_diag.long_title LIKE '%acute myocardial infarction%')
),
first_troponin AS (
    SELECT 
        l.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab 
        ON l.itemid = d_lab.itemid
    WHERE 
        l.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
        AND LOWER(d_lab.label) LIKE '%high sensitivity%troponin%t%'
        AND l.valuenum IS NOT NULL
        AND l.valueuom = 'ng/L'
)
SELECT 
    CASE 
        WHEN ft.valuenum <= 14 THEN 'normal'
        WHEN ft.valuenum > 14 AND ft.valuenum <= 50 THEN 'borderline'
        ELSE 'myocardial injury'
    END AS category,
    COUNT(*) AS count
FROM first_troponin ft
WHERE ft.rn = 1
GROUP BY category;