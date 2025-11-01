WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.patients
    WHERE gender = 'M'
      AND anchor_age BETWEEN 35 AND 45
),
admissions_with_conditions AS (
    SELECT DISTINCT a.hadm_id, a.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
    INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d 
        ON a.hadm_id = d.hadm_id
    WHERE d.icd_version = 10
      AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07%')
),
troponin_t_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
    WHERE category = 'Cardiac'
      AND label LIKE '%high-sensitivity troponin T%'
),
first_troponin_per_admission AS (
    SELECT 
        le.hadm_id,
        le.valuenum,
        le.ref_range_lower,
        le.ref_range_upper,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
    INNER JOIN troponin_t_items t ON le.itemid = t.itemid
    INNER JOIN admissions_with_conditions a 
        ON le.hadm_id = a.hadm_id
    WHERE le.valuenum IS NOT NULL
      AND le.ref_range_lower IS NOT NULL
      AND le.ref_range_upper IS NOT NULL
)
SELECT 
    CASE 
        WHEN valuenum >= ref_range_lower AND valuenum <= ref_range_upper THEN 'normal'
        WHEN valuenum > ref_range_upper AND valuenum <= ref_range_upper * 1.5 THEN 'borderline'
        WHEN valuenum > ref_range_upper * 1.5 THEN 'myocardial injury'
    END AS category,
    COUNT(*) AS count
FROM first_troponin_per_admission
WHERE rn = 1
GROUP BY category
ORDER BY category;