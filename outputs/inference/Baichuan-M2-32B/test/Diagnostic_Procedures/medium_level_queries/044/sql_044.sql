WITH lower_gi_bleed_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE icd_code IN (
        'K52.2', 'K52.3', 'K52.4', 'K92.2', 'K92.3', 'K92.4', 'K92.5', 'K92.6', 'K92.7', 'K92.8', 'K92.9'
    )
),
non_invasive_diagnostics AS (
    SELECT DISTINCT code AS hcpcs_cd
    FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
    WHERE 
        long_description LIKE '%imaging%' OR
        long_description LIKE '%x-ray%' OR
        long_description LIKE '%ct%' OR
        long_description LIKE '%mri%' OR
        long_description LIKE '%ecg%' OR
        long_description LIKE '%eeg%' OR
        long_description LIKE '%pft%' OR
        long_description LIKE '%pulmonary function%' OR
        long_description LIKE '%ultrasound%' OR
        long_description LIKE '%echo%' OR
        long_description LIKE '%mammography%' OR
        long_description LIKE '%angiography%' OR
        long_description LIKE '%nuclear medicine%' OR
        long_description LIKE '%pet scan%' OR
        long_description LIKE '%spect%' OR
        long_description LIKE '%doppler%' OR
        long_description LIKE '%sonogram%'
),
lower_gi_bleed_admissions AS (
    SELECT 
        d.subject_id, 
        d.hadm_id,
        d.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN lower_gi_bleed_codes c ON d.icd_code = c.icd_code
    WHERE d.icd_version = '10'
),
patient_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.gender,
        p.anchor_age,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 62 AND 72
),
filtered_admissions AS (
    SELECT 
        pa.*,
        lgb.hadm_id AS lgb_hadm_id
    FROM patient_admissions pa
    INNER JOIN lower_gi_bleed_admissions lgb 
        ON pa.subject_id = lgb.subject_id AND pa.hadm_id = lgb.hadm_id
    WHERE 
        pa.los_days BETWEEN 1 AND 7
),
icu_status AS (
    SELECT 
        f.*,
        CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_status
    FROM filtered_admissions f
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON f.hadm_id = i.hadm_id
),
los_group AS (
    SELECT 
        *,
        CASE 
            WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
        END AS los_group
    FROM icu_status
),
diagnostics_per_admission AS (
    SELECT 
        a.hadm_id,
        COUNT(n.hcpcs_cd) AS num_diagnostics  -- Counts non-null matches (each non-invasive event)
    FROM los_group a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h 
        ON a.hadm_id = h.hadm_id
    LEFT JOIN non_invasive_diagnostics n 
        ON h.hcpcs_cd = n.hcpcs_cd
    GROUP BY a.hadm_id
),
final_table AS (
    SELECT 
        los_group,
        icu_status,
        AVG(num_diagnostics) AS mean_num_diagnostics
    FROM los_group
    LEFT JOIN diagnostics_per_admission d 
        ON los_group.hadm_id = d.hadm_id
    GROUP BY los_group, icu_status
)
SELECT 
    los_group,
    icu_status,
    mean_num_diagnostics
FROM final_table
ORDER BY los_group, icu_status;