WITH diabetes_adms AS (
    SELECT DISTINCT
        d.subject_id,
        d.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
        -- ICD-9 codes for diabetes (250.xx)
        (d.icd_version = 9 AND d.icd_code LIKE '250%')
        OR
        -- ICD-10 codes for diabetes (E10-E14 family)
        (d.icd_version = 10 AND (
            LEFT(d.icd_code, 3) = 'E10' OR
            LEFT(d.icd_code, 3) = 'E11' OR
            LEFT(d.icd_code, 3) = 'E12' OR
            LEFT(d.icd_code, 3) = 'E13' OR
            LEFT(d.icd_code, 3) = 'E14'
        ))
),
acute_hf_adms AS (
    SELECT DISTINCT
        d.subject_id,
        d.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
        -- ICD-9 codes for heart failure (428.xx)
        (d.icd_version = 9 AND d.icd_code LIKE '428%')
        OR
        -- ICD-10 codes for heart failure (I50.xx)
        (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I50')
),
target_cohort AS (
    -- Defines the patient population: Males 68-78 with diabetes and acute HF
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        diabetes_adms d_ad ON ad.subject_id = d_ad.subject_id AND ad.hadm_id = d_ad.hadm_id
    INNER JOIN
        acute_hf_adms hf_ad ON ad.subject_id = hf_ad.subject_id AND ad.hadm_id = hf_ad.hadm_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 68 AND 78
        AND ad.dischtime IS NOT NULL -- Ensure a valid discharge time for final 24h calculation
),
medication_flags AS (
    -- Identify medication prescriptions (insulin or oral agent) for the target cohort
    SELECT
        tc.subject_id,
        tc.hadm_id,
        tc.admittime,
        tc.dischtime,
        p.starttime,
        -- Flags for medication type (insulin or oral agent)
        CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END AS is_insulin,
        CASE
            WHEN
                LOWER(p.drug) LIKE '%metformin%' OR
                LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR
                LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' OR
                LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR
                LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' OR
                LOWER(p.drug) LIKE '%repaglinide%' OR LOWER(p.drug) LIKE '%nateglinide%' OR
                LOWER(p.drug) LIKE '%acarbose%'
            THEN 1
            ELSE 0
        END AS is_oral_agent
    FROM
        target_cohort tc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON tc.subject_id = p.subject_id AND tc.hadm_id = p.hadm_id
    WHERE
        -- Pre-filter prescriptions to relevant drug types for efficiency
        (LOWER(p.drug) LIKE '%insulin%' OR
         LOWER(p.drug) LIKE '%metformin%' OR
         LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR
         LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' OR
         LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR
         LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' OR
         LOWER(p.drug) LIKE '%repaglinide%' OR LOWER(p.drug) LIKE '%nateglinide%' OR
         LOWER(p.drug) LIKE '%acarbose%'
        )
),
admission_medication_summary AS (
    -- Determine if insulin or oral agents were initiated within specific time windows for each admission
    SELECT
        tc.subject_id,
        tc.hadm_id,
        -- Flag if insulin was prescribed in the first 24 hours of admission
        MAX(COALESCE(mf.is_insulin * CASE WHEN mf.starttime >= tc.admittime AND mf.starttime <= DATETIME_ADD(tc.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END, 0)) AS insulin_first_24h_flag,
        -- Flag if an oral agent was prescribed in the first 24 hours of admission
        MAX(COALESCE(mf.is_oral_agent * CASE WHEN mf.starttime >= tc.admittime AND mf.starttime <= DATETIME_ADD(tc.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END, 0)) AS oral_first_24h_flag,
        -- Flag if insulin was prescribed in the final 24 hours before discharge
        MAX(COALESCE(mf.is_insulin * CASE WHEN mf.starttime >= DATETIME_SUB(tc.dischtime, INTERVAL 24 HOUR) AND mf.starttime <= tc.dischtime THEN 1 ELSE 0 END, 0)) AS insulin_final_24h_flag,
        -- Flag if an oral agent was prescribed in the final 24 hours before discharge
        MAX(COALESCE(mf.is_oral_agent * CASE WHEN mf.starttime >= DATETIME_SUB(tc.dischtime, INTERVAL 24 HOUR) AND mf.starttime <= tc.dischtime THEN 1 ELSE 0 END, 0)) AS oral_final_24h_flag
    FROM
        target_cohort tc
    LEFT JOIN -- Use LEFT JOIN to include admissions with no relevant medication prescriptions
        medication_flags mf ON tc.hadm_id = mf.hadm_id AND tc.subject_id = mf.subject_id
    GROUP BY
        tc.subject_id, tc.hadm_id
)
-- Final selection to calculate percentages and differences
SELECT
    COUNT(DISTINCT ams.hadm_id) AS total_admissions,
    SUM(ams.insulin_first_24h_flag) AS insulin_first_24h_count,
    SUM(ams.oral_first_24h_flag) AS oral_first_24h_count,
    SUM(ams.insulin_final_24h_flag) AS insulin_final_24h_count,
    SUM(ams.oral_final_24h_flag) AS oral_final_24h_count,
    -- Insulin initiation rate in first 24h
    (SUM(ams.insulin_first_24h_flag) * 100.0 / COUNT(DISTINCT ams.hadm_id)) AS insulin_first_24h_rate_pct,
    -- Oral agent initiation rate in first 24h
    (SUM(ams.oral_first_24h_flag) * 100.0 / COUNT(DISTINCT ams.hadm_id)) AS oral_first_24h_rate_pct,
    -- Insulin initiation rate in final 24h
    (SUM(ams.insulin_final_24h_flag) * 100.0 / COUNT(DISTINCT ams.hadm_id)) AS insulin_final_24h_rate_pct,
    -- Oral agent initiation rate in final 24h
    (SUM(ams.oral_final_24h_flag) * 100.0 / COUNT(DISTINCT ams.hadm_id)) AS oral_final_24h_rate_pct,
    -- Absolute percentage-point difference for first 24h (Insulin - Oral Agent)
    ((SUM(ams.insulin_first_24h_flag) - SUM(ams.oral_first_24h_flag)) * 100.0 / COUNT(DISTINCT ams.hadm_id)) AS diff_insulin_oral_first_24h_pct,
    -- Absolute percentage-point difference for final 24h (Insulin - Oral Agent)
    ((SUM(ams.insulin_final_24h_flag) - SUM(ams.oral_final_24h_flag)) * 100.0 / COUNT(DISTINCT ams.hadm_id)) AS diff_insulin_oral_final_24h_pct
FROM
    admission_medication_summary ams;