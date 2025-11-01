WITH Admissions_Age_Gender AS (
    -- 1. Identify all female hospital admissions for patients aged 59-69
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag,
        pat.gender,
        pat.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
),
Patient_Diagnoses AS (
    -- 2. Retrieve all diagnoses for the identified admissions
    SELECT
        ag.subject_id,
        ag.hadm_id,
        ag.admittime,
        ag.dischtime,
        ag.deathtime,
        ag.hospital_expire_flag,
        ag.anchor_age,
        diag.icd_code,
        diag.icd_version
    FROM
        Admissions_Age_Gender ag
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ag.subject_id = diag.subject_id AND ag.hadm_id = diag.hadm_id
),
PE_Comorbidity_Status AS (
    -- 3. Determine if an admission has PE and calculate a simplified comorbidity score
    --    Simplified comorbidity score: Count of distinct major ICD chapters (first 3 chars)
    --    for diagnoses OTHER THAN PE.
    SELECT
        pd.subject_id,
        pd.hadm_id,
        pd.admittime,
        pd.dischtime,
        pd.deathtime,
        pd.hospital_expire_flag,
        pd.anchor_age,
        MAX(CASE WHEN (pd.icd_version = 10 AND pd.icd_code LIKE 'I26%') OR (pd.icd_version = 9 AND pd.icd_code LIKE '415.1%') THEN 1 ELSE 0 END) AS has_pe,
        COUNT(DISTINCT
            CASE
                -- Exclude PE-related codes when counting comorbidities
                WHEN (pd.icd_version = 10 AND pd.icd_code NOT LIKE 'I26%') THEN LEFT(pd.icd_code, 3)
                WHEN (pd.icd_version = 9 AND pd.icd_code NOT LIKE '415.1%') THEN LEFT(pd.icd_code, 3)
                ELSE NULL
            END
        ) AS simplified_comorbidity_score
    FROM
        Patient_Diagnoses pd
    GROUP BY
        pd.subject_id, pd.hadm_id, pd.admittime, pd.dischtime, pd.deathtime, pd.hospital_expire_flag, pd.anchor_age
),
Cardio_Neuro_Complications AS (
    -- 4. Identify admissions with cardiovascular or neurological complications
    --    Cardiovascular (excluding PE): ICD-10 'I%' (excluding 'I26%'), ICD-9 '390'-'459' (excluding '415.1%')
    --    Neurological: ICD-10 'G%' or 'I60'-'I69', ICD-9 '320'-'389' or '430'-'438'
    SELECT
        pd.hadm_id,
        MAX(CASE
            WHEN pd.icd_version = 10 AND (
                (pd.icd_code LIKE 'I%' AND pd.icd_code NOT LIKE 'I26%') OR
                (pd.icd_code LIKE 'G%')
            ) THEN 1
            WHEN pd.icd_version = 9 AND (
                (pd.icd_code BETWEEN '390' AND '459' AND pd.icd_code NOT LIKE '415.1%') OR
                (pd.icd_code BETWEEN '320' AND '389')
            ) THEN 1
            ELSE 0
        END) AS has_cardio_complication,
        MAX(CASE
            WHEN pd.icd_version = 10 AND (
                (pd.icd_code LIKE 'G%') OR
                (pd.icd_code BETWEEN 'I60' AND 'I69')
            ) THEN 1
            WHEN pd.icd_version = 9 AND (
                (pd.icd_code BETWEEN '320' AND '389') OR
                (pd.icd_code BETWEEN '430' AND '438')
            ) THEN 1
            ELSE 0
        END) AS has_neuro_complication
    FROM
        Patient_Diagnoses pd
    GROUP BY
        pd.hadm_id
),
Target_Cohort AS (
    -- 5. Define the target cohort: PE patients with high comorbidity burden
    --    "High comorbidity burden" is defined as simplified_comorbidity_score >= 2
    SELECT
        pcs.*,
        cnc.has_cardio_complication,
        cnc.has_neuro_complication
    FROM
        PE_Comorbidity_Status pcs
    INNER JOIN
        Cardio_Neuro_Complications cnc
        ON pcs.hadm_id = cnc.hadm_id
    WHERE
        pcs.has_pe = 1
        AND pcs.simplified_comorbidity_score >= 2
),
Control_Cohort AS (
    -- 6. Define the control cohort: General inpatients (no PE) of the same age/gender
    SELECT
        pcs.*,
        cnc.has_cardio_complication,
        cnc.has_neuro_complication
    FROM
        PE_Comorbidity_Status pcs
    INNER JOIN
        Cardio_Neuro_Complications cnc
        ON pcs.hadm_id = cnc.hadm_id
    WHERE
        pcs.has_pe = 0
)
-- 7. Aggregate and compare metrics for both cohorts
SELECT
    'Target Cohort (Female, 59-69, PE, High Comorbidity)' AS cohort_name,
    COUNT(hadm_id) AS num_admissions,
    ROUND(AVG(simplified_comorbidity_score), 2) AS mean_simplified_comorbidity_score,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 AND DATE_DIFF(deathtime, admittime, DAY) <= 30 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id), 2) AS thirty_day_mortality_rate_percent,
    ROUND(AVG(CASE WHEN hospital_expire_flag = 0 THEN DATE_DIFF(dischtime, admittime, DAY) END), 2) AS mean_survivor_los_days,
    ROUND(SUM(has_cardio_complication) * 100.0 / COUNT(hadm_id), 2) AS cardio_complication_rate_percent,
    ROUND(SUM(has_neuro_complication) * 100.0 / COUNT(hadm_id), 2) AS neuro_complication_rate_percent,
    CAST(NULL AS STRING) AS matched_profile_percentile_vs_controls -- This metric typically requires external statistical analysis or a pre-defined score/ranking method not directly available in a single MIMIC-IV SQL query.
FROM
    Target_Cohort
UNION ALL
SELECT
    'Control Cohort (Female, 59-69, General Inpatients)' AS cohort_name,
    COUNT(hadm_id) AS num_admissions,
    ROUND(AVG(simplified_comorbidity_score), 2) AS mean_simplified_comorbidity_score,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 AND DATE_DIFF(deathtime, admittime, DAY) <= 30 THEN 1 ELSE 0 END) * 100.0 / COUNT(hadm_id), 2) AS thirty_day_mortality_rate_percent,
    ROUND(AVG(CASE WHEN hospital_expire_flag = 0 THEN DATE_DIFF(dischtime, admittime, DAY) END), 2) AS mean_survivor_los_days,
    ROUND(SUM(has_cardio_complication) * 100.0 / COUNT(hadm_id), 2) AS cardio_complication_rate_percent,
    ROUND(SUM(has_neuro_complication) * 100.0 / COUNT(hadm_id), 2) AS neuro_complication_rate_percent,
    CAST(NULL AS STRING) AS matched_profile_percentile_vs_controls
FROM
    Control_Cohort;