WITH patient_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        p.gender,
        p.anchor_year,
        p.anchor_age,
        -- Compute birth date
        DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date,
        -- Compute age at admission
        TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission,
        -- Compute LOS in days
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) BETWEEN 72 AND 82
),
tia_admissions AS (
    SELECT DISTINCT
        pa.hadm_id
    FROM patient_admissions pa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON pa.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE dd.icd_code LIKE '435.9%' AND dd.icd_version = 9
),
icu_use AS (
    SELECT 
        tia.hadm_id,
        CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_use
    FROM tia_admissions tia
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON tia.hadm_id = i.hadm_id
),
imaging_procedures AS (
    SELECT
        p.hadm_id,
        COUNT(DISTINCT p.seq_num) AS imaging_procedures_count
    FROM tia_admissions tia
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON tia.hadm_id = p.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
        ON p.icd_code = dp.icd_code 
        AND p.icd_version = dp.icd_version
        AND dp.icd_version = 9
        AND (dp.long_title LIKE '%CT%' 
             OR dp.long_title LIKE '%MRI%' 
             OR dp.long_title LIKE '%X-ray%' 
             OR dp.long_title LIKE '%Radiograph%' 
             OR dp.long_title LIKE '%Ultrasound%' 
             OR dp.long_title LIKE '%Scan%' 
             OR dp.long_title LIKE '%Fluoroscopy%' 
             OR dp.long_title LIKE '%Mammography%' 
             OR dp.long_title LIKE '%Angiography%' 
             OR dp.long_title LIKE '%Tomography%'
             OR dp.long_title LIKE '%PET%' 
             OR dp.long_title LIKE '%SPECT%')
    GROUP BY p.hadm_id
),
admission_metrics AS (
    SELECT
        iu.hadm_id,
        iu.icu_use,
        pa.los_days,
        COALESCE(ip.imaging_procedures_count, 0) AS imaging_procedures_count
    FROM tia_admissions tia
    INNER JOIN icu_use iu ON tia.hadm_id = iu.hadm_id
    INNER JOIN patient_admissions pa ON tia.hadm_id = pa.hadm_id
    LEFT JOIN imaging_procedures ip ON tia.hadm_id = ip.hadm_id
    WHERE pa.los_days BETWEEN 1 AND 7
)
SELECT
    icu_use,
    CASE 
        WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    COUNT(hadm_id) AS admission_count,
    AVG(imaging_procedures_count) AS mean_imaging_per_admission
FROM admission_metrics
GROUP BY icu_use, los_group
ORDER BY icu_use, los_group;