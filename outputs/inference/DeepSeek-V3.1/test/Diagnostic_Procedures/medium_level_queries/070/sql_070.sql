WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital,
        CASE 
            WHEN icu.stay_id IS NOT NULL THEN 'Yes' 
            ELSE 'No' 
        END AS icu_used,
        COUNT(DISTINCT proc.icd_code) AS proc_count  -- Count distinct procedures per admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON adm.hadm_id = proc.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 59 AND 69
        AND (
            (diag.icd_code LIKE 'I50%' AND diag.icd_version = 10) OR  -- ICD-10 heart failure
            (diag.icd_code LIKE '428%' AND diag.icd_version = 9)       -- ICD-9 heart failure
        )
        AND (
            -- ICD-10 codes for radiography/CT
            (proc.icd_version = 10 AND (proc.icd_code LIKE 'BW%' OR proc.icd_code LIKE 'B%')) OR
            -- ICD-9 codes for radiography/CT
            (proc.icd_version = 9 AND (proc.icd_code LIKE '87.%' OR proc.icd_code IN ('87.03', '88.01', '88.38')))
        )
    GROUP BY adm.subject_id, adm.hadm_id, los_hospital, icu_used
),
los_groups AS (
    SELECT 
        hadm_id,
        icu_used,
        proc_count,
        CASE 
            WHEN los_hospital BETWEEN 1 AND 4 THEN '1-4'
            WHEN los_hospital BETWEEN 5 AND 8 THEN '5-8'
            ELSE 'Other' 
        END AS los_group
    FROM cohort
    WHERE los_hospital BETWEEN 1 AND 8  -- Only include stays 1-8 days
)
SELECT 
    los_group,
    icu_used,
    APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS p25,
    APPROX_QUANTILES(proc_count, 4)[OFFSET(2)] AS p50,
    APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS p75
FROM los_groups
GROUP BY los_group, icu_used
ORDER BY los_group, icu_used;