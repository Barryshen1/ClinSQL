WITH cohort AS (
    -- Get male patients aged 68-78 with heart failure
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Check for CKD diagnosis
        MAX(CASE 
            WHEN ckd.icd_code IS NOT NULL THEN 1 
            ELSE 0 
        END) AS has_ckd,
        -- Check for diabetes diagnosis
        MAX(CASE 
            WHEN dm.icd_code IS NOT NULL THEN 1 
            ELSE 0 
        END) AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf
        ON adm.hadm_id = hf.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_hf
        ON hf.icd_code = d_hf.icd_code 
        AND hf.icd_version = d_hf.icd_version
    -- Left join for CKD diagnoses
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ckd
        ON adm.hadm_id = ckd.hadm_id
        AND (
            (ckd.icd_version = 10 AND ckd.icd_code LIKE 'N18%') 
            OR (ckd.icd_version = 9 AND ckd.icd_code LIKE '585%')
        )
    -- Left join for diabetes diagnoses
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dm
        ON adm.hadm_id = dm.hadm_id
        AND (
            (dm.icd_version = 10 AND dm.icd_code LIKE 'E10%' OR dm.icd_code LIKE 'E11%' OR dm.icd_code LIKE 'E13%') 
            OR (dm.icd_version = 9 AND dm.icd_code LIKE '250%')
        )
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 68 AND 78
        AND (
            (hf.icd_version = 10 AND d_hf.long_title LIKE '%heart failure%')
            OR (hf.icd_version = 9 AND d_hf.long_title LIKE '%heart failure%')
        )
    GROUP BY adm.subject_id, adm.hadm_id, adm.hospital_expire_flag, los_days
)
SELECT 
    CASE 
        WHEN los_days < 8 THEN '<8 days' 
        ELSE '>=8 days' 
    END AS los_group,
    COUNT(*) AS n_patients,
    ROUND(100 * SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)), 2) AS mortality_percent,
    ROUND(100 * SAFE_DIVIDE(SUM(has_ckd), COUNT(*)), 2) AS ckd_prevalence_percent,
    ROUND(100 * SAFE_DIVIDE(SUM(has_diabetes), COUNT(*)), 2) AS diabetes_prevalence_percent
FROM cohort
GROUP BY los_group
ORDER BY los_group;