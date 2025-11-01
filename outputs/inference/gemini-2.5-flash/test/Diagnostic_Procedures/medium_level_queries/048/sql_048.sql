WITH PatientAdmissions AS (
    -- Step 1: Identify eligible patients and admissions
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        pa.anchor_age, -- Using anchor_age directly as per MIMIC-IV guidelines for age ranges
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 90 AND 100
        -- Filter for LOS 1-7 days as per question's stratification criteria
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 7
),
HeartFailureAdmissions_Raw AS (
    -- Step 2: Identify Heart Failure (HF) diagnoses and initial classification for each eligible admission
    SELECT
        pa.subject_id,
        pa.hadm_id,
        pa.los_days,
        -- Determine if any diagnosis with seq_num=1 is HF
        MAX(CASE
            WHEN dg.seq_num = 1 AND
                 (
                    (dg.icd_version = 9 AND (dg.icd_code LIKE '428%' OR dg.icd_code IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493'))) OR
                    (dg.icd_version = 10 AND (dg.icd_code LIKE 'I50%' OR dg.icd_code IN ('I110', 'I130', 'I132')))
                    OR LOWER(did.long_title) LIKE '%heart failure%'
                 )
            THEN 1 ELSE 0 END) AS has_primary_hf_diagnosis,
        -- Determine if any diagnosis with seq_num > 1 is HF
        MAX(CASE
            WHEN dg.seq_num > 1 AND
                 (
                    (dg.icd_version = 9 AND (dg.icd_code LIKE '428%' OR dg.icd_code IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493'))) OR
                    (dg.icd_version = 10 AND (dg.icd_code LIKE 'I50%' OR dg.icd_code IN ('I110', 'I130', 'I132')))
                    OR LOWER(did.long_title) LIKE '%heart failure%'
                 )
            THEN 1 ELSE 0 END) AS has_secondary_hf_diagnosis
    FROM
        PatientAdmissions pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dg
        ON pa.subject_id = dg.subject_id AND pa.hadm_id = dg.hadm_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON dg.icd_code = did.icd_code AND dg.icd_version = did.icd_version
    WHERE
        -- Filter for rows that are actually Heart Failure diagnoses directly in the WHERE clause
        (
            (dg.icd_version = 9 AND (dg.icd_code LIKE '428%' OR dg.icd_code IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493'))) OR
            (dg.icd_version = 10 AND (dg.icd_code LIKE 'I50%' OR dg.icd_code IN ('I110', 'I130', 'I132')))
            OR LOWER(did.long_title) LIKE '%heart failure%'
        )
    GROUP BY
        pa.subject_id, pa.hadm_id, pa.los_days
),
ClassifiedHFAdmissions AS (
    -- Step 2 (cont.): Classify each admission as 'Primary HF' or 'Secondary HF' and LOS group
    SELECT
        subject_id,
        hadm_id,
        los_days,
        CASE
            WHEN has_primary_hf_diagnosis = 1 THEN 'Primary HF'
            WHEN has_secondary_hf_diagnosis = 1 THEN 'Secondary HF'
            ELSE 'No HF' -- Should be filtered out if no HF is found
        END AS hf_diagnosis_type,
        CASE
            WHEN los_days BETWEEN 1 AND 3 THEN 'LOS 1-3'
            WHEN los_days BETWEEN 4 AND 7 THEN 'LOS 4-7'
            ELSE NULL -- Filtered by PatientAdmissions CTE
        END AS los_group
    FROM
        HeartFailureAdmissions_Raw
    WHERE
        has_primary_hf_diagnosis = 1 OR has_secondary_hf_diagnosis = 1 -- Ensure the admission has at least one HF diagnosis
),
MRI_CT_Counts AS (
    -- Step 3: Count MRI/CT procedures per eligible admission
    SELECT
        pa.subject_id,
        pa.hadm_id,
        -- Count each procedure record that matches the MRI/CT criteria
        COUNT(pi.icd_code) AS mri_ct_procedures_count
    FROM
        PatientAdmissions pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        ON pa.subject_id = pi.subject_id AND pa.hadm_id = pi.hadm_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
    WHERE
        -- Identify MRI/CT related procedures using keywords in long_title
        LOWER(dp.long_title) LIKE '%ct scan%' OR LOWER(dp.long_title) LIKE '%computed tomography%' OR
        LOWER(dp.long_title) LIKE '%mri%' OR LOWER(dp.long_title) LIKE '%magnetic resonance%'
    GROUP BY
        pa.subject_id, pa.hadm_id
)
-- Step 4: Combine and Aggregate results
SELECT
    chfa.los_group,
    chfa.hf_diagnosis_type,
    COUNT(DISTINCT chfa.hadm_id) AS admission_count,
    COALESCE(AVG(mcc.mri_ct_procedures_count), 0) AS mean_mri_ct_per_admission
FROM
    ClassifiedHFAdmissions chfa
LEFT JOIN -- Use LEFT JOIN to include admissions with no MRI/CT procedures
    MRI_CT_Counts mcc
    ON chfa.subject_id = mcc.subject_id AND chfa.hadm_id = mcc.hadm_id
GROUP BY
    chfa.los_group,
    chfa.hf_diagnosis_type
ORDER BY
    chfa.los_group,
    chfa.hf_diagnosis_type;