WITH cohort AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        p.anchor_year,
        a.hospital_expire_flag,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'  -- Fixed: moved gender condition to patients table
        AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 67 AND 77
),
acs_diagnoses AS (
    SELECT 
        d.hadm_id,
        d.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE 
        d.seq_num = 1
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%')
),
troponin_first AS (
    SELECT 
        l.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl 
        ON l.itemid = dl.itemid
    WHERE 
        dl.label LIKE '%Troponin T%'  -- Changed from loinc_code to label due to error
        AND l.valueuom = 'ng/mL'
),
troponin_categorized AS (
    SELECT 
        c.hadm_id,
        c.subject_id,
        c.hospital_expire_flag,
        CASE 
            WHEN t.valuenum <= 0.04 THEN 'normal'
            WHEN t.valuenum > 0.04 AND t.valuenum <= 0.1 THEN 'borderline'
            WHEN t.valuenum > 0.1 THEN 'elevated'
            ELSE 'missing'
        END AS troponin_category
    FROM cohort c
    INNER JOIN acs_diagnoses ad 
        ON c.hadm_id = ad.hadm_id
    INNER JOIN troponin_first t 
        ON c.hadm_id = t.hadm_id
    WHERE t.rn = 1
    AND t.valuenum IS NOT NULL
),
total_admissions AS (
    SELECT COUNT(*) AS total_count
    FROM troponin_categorized
)
SELECT 
    troponin_category,
    COUNT(*) AS count_admissions,
    ROUND((COUNT(*) * 100.0) / (SELECT total_count FROM total_admissions), 2) AS percent_admissions,
    ROUND((SUM(hospital_expire_flag) * 100.0) / COUNT(*), 2) AS mortality_rate
FROM troponin_categorized
GROUP BY troponin_category
ORDER BY 
    CASE troponin_category
        WHEN 'normal' THEN 1
        WHEN 'borderline' THEN 2
        WHEN 'elevated' THEN 3
    END;