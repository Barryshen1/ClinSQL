WITH eligible_patients AS (
    SELECT
        p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 77 AND 87  -- Changed to 77-87 as per clinical question
),
asthma_admissions AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,  -- Fixed function name and added DAY
        -- ICU status: check for any ICU stay in the admission
        CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN eligible_patients ep
        ON a.subject_id = ep.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE a.dischtime IS NOT NULL
        -- Filter for asthma exacerbation using ICD-10 codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON d.icd_code = dd.icd_code
                AND d.icd_version = dd.icd_version
            WHERE d.hadm_id = a.hadm_id
                AND dd.icd_version = 10
                AND (dd.icd_code LIKE 'J45%' OR dd.icd_code LIKE 'J46%') -- Common asthma codes
        )
),
ct_mri_counts AS (
    SELECT
        a.hadm_id,
        COUNT(DISTINCT h.hcpcs_cd) AS ct_mri_count -- Count distinct HCPCS codes per admission
    FROM asthma_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
        ON a.hadm_id = h.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
        ON h.hcpcs_cd = dh.code
    WHERE 
        -- Filter for CT or MRI in the description (case-insensitive)
        (dh.long_description LIKE '%CT%' OR dh.long_description LIKE '%MRI%')
    GROUP BY a.hadm_id
),
final_data AS (
    SELECT
        a.icu_status,
        -- Group LOS into 1-4 and 5-8 days
        CASE 
            WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN a.los_days BETWEEN 5 AND 8 THEN '5-8 days'
            ELSE NULL 
        END AS los_group,
        c.ct_mri_count
    FROM asthma_admissions a
    LEFT JOIN ct_mri_counts c
        ON a.hadm_id = c.hadm_id
    WHERE 
        -- Only include admissions with LOS in 1-4 or 5-8 days (simplified condition)
        a.los_days BETWEEN 1 AND 8
)
SELECT
    icu_status,
    los_group,
    COUNT(*) AS num_admissions, -- Number of admissions in each group
    AVG(ct_mri_count) AS mean_ct_mri,
    MIN(ct_mri_count) AS min_ct_mri,
    MAX(ct_mri_count) AS max_ct_mri
FROM final_data
GROUP BY icu_status, los_group
ORDER BY icu_status, los_group;