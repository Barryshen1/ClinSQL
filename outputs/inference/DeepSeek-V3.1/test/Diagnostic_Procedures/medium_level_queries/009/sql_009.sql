WITH cohort AS (
    -- Get female patients aged 44-54 with TIA diagnosis
    SELECT DISTINCT p.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 44 AND 54
        AND dd.icd_code LIKE 'G45%'
        AND di.icd_version = 10
),
los_icu AS (
    -- Compute LOS and ICU usage for each admission
    SELECT 
        c.subject_id,
        c.hadm_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE 
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
            ELSE 'Other' 
        END AS los_group,
        CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_used
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON c.hadm_id = a.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON c.hadm_id = i.hadm_id
),
imaging_procedures AS (
    -- Count imaging procedures per admission from procedures_icd (ICD-10-PCS)
    SELECT hadm_id, COUNT(DISTINCT icd_code) AS imaging_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE icd_version = 10
        AND icd_code LIKE 'B%'
    GROUP BY hadm_id
    UNION ALL
    -- Count imaging procedures per admission from hcpcsevents (HCPCS)
    SELECT hadm_id, COUNT(DISTINCT hcpcs_cd) AS imaging_count
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE hcpcs_cd IN (
        '71250', '71260', '71270', -- CT thorax
        '70450', '70460', '70470', '70480', '70481', '70482', -- CT head
        '70551', '70552', '70553', -- MRI brain
        '72141', '72142', '72146', '72147', '72148', -- MRI spine
        '74150', '74160', '74170', '74181', '74182', '74183' -- CT abdomen
    )
    GROUP BY hadm_id
),
imaging_per_admission AS (
    -- Combine imaging counts from both sources
    SELECT hadm_id, SUM(imaging_count) AS total_imaging
    FROM imaging_procedures
    GROUP BY hadm_id
),
admissions_with_imaging AS (
    -- Join LOS/ICU with imaging counts (include zeros)
    SELECT 
        li.hadm_id,
        li.los_group,
        li.icu_used,
        COALESCE(ip.total_imaging, 0) AS imaging_count
    FROM los_icu li
    LEFT JOIN imaging_per_admission ip
        ON li.hadm_id = ip.hadm_id
    WHERE li.los_group IN ('1-4', '5-7')
)
-- Compute percentiles by LOS group and ICU usage
SELECT 
    los_group,
    icu_used,
    COUNT(*) AS num_admissions,
    APPROX_QUANTILES(imaging_count, 100) [SAFE_ORDINAL(25)] AS p25_imaging,
    APPROX_QUANTILES(imaging_count, 100) [SAFE_ORDINAL(50)] AS p50_imaging,
    APPROX_QUANTILES(imaging_count, 100) [SAFE_ORDINAL(75)] AS p75_imaging
FROM admissions_with_imaging
GROUP BY los_group, icu_used
ORDER BY los_group, icu_used;