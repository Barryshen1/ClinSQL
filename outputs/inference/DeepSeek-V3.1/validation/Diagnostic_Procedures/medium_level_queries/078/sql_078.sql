WITH tia_patients AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 88 AND 98
        AND (d.icd_code LIKE '435%' OR d.icd_code LIKE 'G45%')
),
icu_flag AS (
    SELECT tp.hadm_id,
        MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_icu
    FROM tia_patients tp
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON tp.hadm_id = i.hadm_id
    GROUP BY tp.hadm_id
),
los_data AS (
    SELECT a.hadm_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            ELSE 'Other'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN tia_patients tp ON a.hadm_id = tp.hadm_id
),
imaging AS (
    SELECT hadm_id, COUNT(*) AS imaging_count
    FROM (
        -- ICD procedures for CT/MRI
        SELECT proc.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        INNER JOIN tia_patients tp ON proc.hadm_id = tp.hadm_id
        WHERE 
            (proc.icd_version = 9 AND (
                proc.icd_code LIKE '87.0%' OR  -- CT scans
                proc.icd_code LIKE '88.0%' OR  -- CT scans
                proc.icd_code LIKE '88.3%' OR  -- MRI
                proc.icd_code LIKE '88.4%'     -- MRI
            )) OR
            (proc.icd_version = 10 AND (
                proc.icd_code LIKE 'BW2%' OR   -- CT scans
                proc.icd_code LIKE 'BW3%' OR   -- CT scans  
                proc.icd_code LIKE 'BW4%' OR   -- CT scans
                proc.icd_code LIKE 'B11%'      -- MRI
            ))
        
        UNION ALL
        
        -- HCPCS codes for CT/MRI
        SELECT hcpc.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
        INNER JOIN tia_patients tp ON hcpc.hadm_id = tp.hadm_id
        WHERE 
            hcpc.hcpcs_cd LIKE '7%' AND (  -- Radiology codes
                hcpc.hcpcs_cd LIKE '704%' OR  -- CT head
                hcpc.hcpcs_cd LIKE '705%' OR  -- MRI
                hcpc.hcpcs_cd LIKE '721%' OR  -- CT spine
                hcpc.hcpcs_cd LIKE '741%'     -- CT abdomen
            )
    ) AS imaging_events
    GROUP BY hadm_id
),
combined AS (
    SELECT 
        ld.hadm_id,
        ld.los_group,
        ifl.had_icu,
        COALESCE(img.imaging_count, 0) AS imaging_count
    FROM los_data ld
    INNER JOIN icu_flag ifl ON ld.hadm_id = ifl.hadm_id
    LEFT JOIN imaging img ON ld.hadm_id = img.hadm_id
    WHERE ld.los_group IN ('1-3', '4-7')
)
SELECT 
    los_group,
    had_icu,
    COUNT(*) AS num_admissions,
    APPROX_QUANTILES(imaging_count, 100)[OFFSET(50)] AS median_imaging,
    APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS q1_imaging,
    APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS q3_imaging
FROM combined
GROUP BY los_group, had_icu
ORDER BY los_group, had_icu;