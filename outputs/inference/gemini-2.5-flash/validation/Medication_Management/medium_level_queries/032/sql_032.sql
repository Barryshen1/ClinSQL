WITH cohort_admissions AS (
    -- Identify the target cohort: male inpatients aged 51-61 with diabetes and acute heart failure
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 51 AND 61
        -- Check for Diabetes Mellitus diagnosis (ICD-10 codes E08-E13)
        AND EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_dm
            WHERE di_dm.subject_id = a.subject_id
            AND di_dm.hadm_id = a.hadm_id
            AND di_dm.icd_version = 10
            AND di_dm.icd_code BETWEEN 'E08' AND 'E139' -- Covers E08.xx to E13.xx
        )
        -- Check for Acute Heart Failure diagnosis (ICD-10 code I50.%)
        AND EXISTS (
            SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_ahf
            WHERE di_ahf.subject_id = a.subject_id
            AND di_ahf.hadm_id = a.hadm_id
            AND di_ahf.icd_version = 10
            AND di_ahf.icd_code LIKE 'I50.%'
        )
),
insulin_prescriptions_raw AS (
    -- Get all insulin prescriptions for the cohort and classify them
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        p.starttime,
        p.drug,
        -- Classify Basal insulin (long-acting)
        -- Common basal insulins: Glargine, Detemir, Degludec (Lantus, Levemir, Tresiba, Toujeo)
        CASE WHEN REGEXP_CONTAINS(LOWER(p.drug), '(glargine|detemir|degludec|lantus|levimir|tresiba|toujeo)') THEN 1 ELSE 0 END AS is_basal_insulin,
        -- Classify Bolus insulin (rapid/short-acting)
        -- Common bolus insulins: Lispro, Aspart, Glulisine, Regular (Humalog, Novolog, Apidra, Humulin R, Novolin R)
        CASE WHEN REGEXP_CONTAINS(LOWER(p.drug), '(lispro|aspart|glulisine|regular insulin|humalog|novolog|apidra|humulin r|novolin r)') THEN 1 ELSE 0 END AS is_bolus_insulin,
        -- Classify Sliding-Scale insulin
        CASE WHEN REGEXP_CONTAINS(LOWER(p.drug), '(sliding scale|ss insulin)') THEN 1 ELSE 0 END AS is_ss_insulin
    FROM
        cohort_admissions ca
    JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON ca.subject_id = p.subject_id AND ca.hadm_id = p.hadm_id
    WHERE
        LOWER(p.drug) LIKE '%insulin%' -- Ensure it's an insulin-related drug
        -- Filter prescriptions to within the relevant admission period
        AND p.starttime BETWEEN ca.admittime AND ca.dischtime
),
patient_regimens_flags AS (
    -- Aggregate prescription types per admission for each time window
    SELECT
        subject_id,
        hadm_id,
        admittime, -- Included for grouping
        dischtime, -- Included for grouping
        -- Flags for the first 24 hours of admission
        MAX(CASE WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 24 HOUR) AND is_basal_insulin = 1 THEN 1 ELSE 0 END) AS has_basal_24h,
        MAX(CASE WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 24 HOUR) AND is_bolus_insulin = 1 THEN 1 ELSE 0 END) AS has_bolus_24h,
        MAX(CASE WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 24 HOUR) AND is_ss_insulin = 1 THEN 1 ELSE 0 END) AS has_ss_insulin_24h,
        (MAX(CASE WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 24 HOUR) AND is_basal_insulin = 1 THEN 1 ELSE 0 END) *
         MAX(CASE WHEN starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 24 HOUR) AND is_bolus_insulin = 1 THEN 1 ELSE 0 END)) AS has_basal_bolus_24h, -- Logical AND for Basal-Bolus

        -- Flags for the final 12 hours of admission
        MAX(CASE WHEN starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime AND is_basal_insulin = 1 THEN 1 ELSE 0 END) AS has_basal_12h,
        MAX(CASE WHEN starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime AND is_bolus_insulin = 1 THEN 1 ELSE 0 END) AS has_bolus_12h,
        MAX(CASE WHEN starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime AND is_ss_insulin = 1 THEN 1 ELSE 0 END) AS has_ss_insulin_12h,
        (MAX(CASE WHEN starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime AND is_basal_insulin = 1 THEN 1 ELSE 0 END) *
         MAX(CASE WHEN starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime AND is_bolus_insulin = 1 THEN 1 ELSE 0 END)) AS has_basal_bolus_12h  -- Logical AND for Basal-Bolus

    FROM
        insulin_prescriptions_raw
    GROUP BY
        subject_id, hadm_id, admittime, dischtime -- Added admittime and dischtime to GROUP BY
),
overall_cohort_counts AS (
    -- Count total unique admissions in the cohort
    SELECT
        COUNT(DISTINCT hadm_id) AS total_cohort_admissions
    FROM cohort_admissions
)
-- Calculate prevalence and percentage-point change
SELECT
    regimen_type,
    ROUND(prevalence_24h_percent, 2) AS prevalence_first_24h_percent,
    ROUND(prevalence_12h_percent, 2) AS prevalence_final_12h_percent,
    ROUND(prevalence_12h_percent - prevalence_24h_percent, 2) AS percentage_point_change
FROM (
    SELECT
        'Basal' AS regimen_type,
        SAFE_DIVIDE(SUM(has_basal_24h), (SELECT total_cohort_admissions FROM overall_cohort_counts)) * 100 AS prevalence_24h_percent,
        SAFE_DIVIDE(SUM(has_basal_12h), (SELECT total_cohort_admissions FROM overall_cohort_counts)) * 100 AS prevalence_12h_percent
    FROM patient_regimens_flags
    UNION ALL
    SELECT
        'Bolus' AS regimen_type,
        SAFE_DIVIDE(SUM(has_bolus_24h), (SELECT total_cohort_admissions FROM overall_cohort_counts)) * 100 AS prevalence_24h_percent,
        SAFE_DIVIDE(SUM(has_bolus_12h), (SELECT total_cohort_admissions FROM overall_cohort_counts)) * 100 AS prevalence_12h_percent
    FROM patient_regimens_flags
    UNION ALL
    SELECT
        'Sliding-Scale' AS regimen_type,
        SAFE_DIVIDE(SUM(has_ss_insulin_24h), (SELECT total_cohort_admissions FROM overall_cohort_counts)) * 100 AS prevalence_24h_percent,
        SAFE_DIVIDE(SUM(has_ss_insulin_12h), (SELECT total_cohort_admissions FROM overall_cohort_counts)) * 100 AS prevalence_12h_percent
    FROM patient_regimens_flags
    UNION ALL
    SELECT
        'Basal-Bolus' AS regimen_type,
        SAFE_DIVIDE(SUM(has_basal_bolus_24h), (SELECT total_cohort_admissions FROM overall_cohort_counts)) * 100 AS prevalence_24h_percent,
        SAFE_DIVIDE(SUM(has_basal_bolus_12h), (SELECT total_cohort_admissions FROM overall_cohort_counts)) * 100 AS prevalence_12h_percent
    FROM patient_regimens_flags
)
ORDER BY regimen_type;