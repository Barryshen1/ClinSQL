WITH ami_patients AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 64 AND 74
),
ami_diagnoses AS (
    SELECT 
        ami.subject_id,
        ami.hadm_id,
        ami.admittime
    FROM ami_patients ami
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ami.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'
        AND diag.icd_version = 10
    GROUP BY ami.subject_id, ami.hadm_id, ami.admittime
),
first_troponin AS (
    SELECT 
        ad.subject_id,
        ad.hadm_id,
        le.charttime,
        le.valuenum AS troponin_value
    FROM ami_diagnoses ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ad.hadm_id = le.hadm_id
    WHERE le.itemid = 50911  -- High-sensitivity troponin T
        AND le.valuenum IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ad.hadm_id ORDER BY le.charttime) = 1
)
SELECT 
    CASE 
        WHEN troponin_value <= 0.014 THEN 'Normal (≤0.014)'
        WHEN troponin_value <= 0.052 THEN 'Borderline (0.015–0.052)'
        ELSE 'Myocardial Injury (>0.052)'
    END AS troponin_category,
    COUNT(*) AS patient_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM first_troponin
GROUP BY troponin_category
ORDER BY troponin_category;