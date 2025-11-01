WITH acs_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 67 AND 77
        AND diag.icd_version = 10
        AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code LIKE 'I24%')
),
first_troponin_t AS (
    SELECT 
        lab.hadm_id,
        lab.charttime,
        lab.valuenum AS troponin_value,
        ROW_NUMBER() OVER (PARTITION BY lab.hadm_id ORDER BY lab.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
    INNER JOIN acs_admissions adm 
        ON lab.hadm_id = adm.hadm_id
    WHERE 
        lab.itemid = 51004  -- Quantitative Troponin T
        AND lab.valuenum IS NOT NULL
),
categorized_troponin AS (
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        CASE 
            WHEN trop.troponin_value <= 0.04 THEN 'Normal (≤0.04)'
            WHEN trop.troponin_value > 0.04 AND trop.troponin_value <= 0.1 THEN 'Borderline (>0.04-0.1)'
            WHEN trop.troponin_value > 0.1 THEN 'Elevated (>0.1)'
        END AS troponin_category
    FROM acs_admissions adm
    INNER JOIN first_troponin_t trop
        ON adm.hadm_id = trop.hadm_id
    WHERE trop.rn = 1
)
SELECT
    troponin_category,
    COUNT(*) AS admission_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_troponin), 2) AS percent_of_admissions,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS in_hospital_mortality_rate_percent
FROM categorized_troponin
GROUP BY troponin_category
ORDER BY 
    CASE troponin_category
        WHEN 'Normal (≤0.04)' THEN 1
        WHEN 'Borderline (>0.04-0.1)' THEN 2
        WHEN 'Elevated (>0.1)' THEN 3
    END;