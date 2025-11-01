WITH ami_icd_codes AS (
    SELECT 'I21%' AS icd_code_pattern, 10 AS icd_version UNION ALL
    SELECT 'I22%' AS icd_code_pattern, 10 AS icd_version UNION ALL
    SELECT '410%' AS icd_code_pattern, 9 AS icd_version
),
-- Define ICD codes for Major Complications
-- Note: This is a representative list of common severe complications.
-- A precise definition of "major complication" may vary clinically.
major_complication_icd_codes AS (
    SELECT 'A40%' AS icd_code_pattern UNION ALL -- Sepsis
    SELECT 'A41%' AS icd_code_pattern UNION ALL -- Sepsis
    SELECT 'R65%' AS icd_code_pattern UNION ALL -- SIRS/Sepsis
    SELECT 'N17%' AS icd_code_pattern UNION ALL -- Acute Kidney Injury
    SELECT 'J96%' AS icd_code_pattern UNION ALL -- Respiratory Failure
    SELECT 'I82%' AS icd_code_pattern UNION ALL -- DVT
    SELECT 'I26%' AS icd_code_pattern UNION ALL -- Pulmonary Embolism
    SELECT 'I63%' AS icd_code_pattern UNION ALL -- Ischemic Stroke
    SELECT 'I61%' AS icd_code_pattern UNION ALL -- Intracerebral Hemorrhage
    SELECT 'I60%' AS icd_code_pattern UNION ALL -- Subarachnoid Hemorrhage
    SELECT 'K92%' AS icd_code_pattern UNION ALL -- Gastrointestinal Hemorrhage
    SELECT 'I46%' AS icd_code_pattern          -- Cardiac Arrest
),
-- Base Admissions: Demographics, calculated age, LOS, and mortality flags for initial filtering
base_admissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        pat.gender,
        pat.anchor_age,
        pat.anchor_year,
        pat.dod,
        -- Calculate age at admission
        CAST(EXTRACT(YEAR FROM ad.admittime) - pat.anchor_year + pat.anchor_age AS INT64) AS age_at_admission,
        -- Calculate hospital length of stay
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_hospital_days,
        -- Flag for 90-day mortality from admission
        (COALESCE(ad.deathtime, pat.dod) IS NOT NULL AND DATE_DIFF(COALESCE(ad.deathtime, pat.dod), ad.admittime, DAY) <= 90) AS is_90_day_mortality_flag,
        -- Flag for 90-day survivor (used for LOS calculations)
        (COALESCE(ad.deathtime, pat.dod) IS NULL OR DATE_DIFF(COALESCE(ad.deathtime, pat.dod), ad.admittime, DAY) > 90) AS is_90_day_survivor_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
    WHERE
        -- Initial age-matching filter for both groups
        CAST(EXTRACT(YEAR FROM ad.admittime) - pat.anchor_year + pat.anchor_age AS INT64) BETWEEN 68 AND 78
        AND ad.admittime IS NOT NULL AND ad.dischtime IS NOT NULL AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) >= 0 -- Exclude admissions with invalid LOS
),
-- Identify admissions with an AMI diagnosis
admissions_with_ami AS (
    SELECT DISTINCT ba.hadm_id
    FROM base_admissions ba
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ba.hadm_id = di.hadm_id
    INNER JOIN ami_icd_codes aic
        ON di.icd_code LIKE aic.icd_code_pattern AND di.icd_version = aic.icd_version
),
-- Identify admissions with an ICU stay
admissions_with_icu AS (
    SELECT DISTINCT ba.hadm_id
    FROM base_admissions ba
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ba.hadm_id = icu.hadm_id
),
-- Identify admissions with any of the defined major complications
admissions_with_major_complication AS (
    SELECT DISTINCT ba.hadm_id
    FROM base_admissions ba
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ba.hadm_id = di.hadm_id
    INNER JOIN major_complication_icd_codes mcic
        ON di.icd_code LIKE mcic.icd_code_pattern
),
-- Get DRG severity as a proxy for risk score (max severity per admission)
drg_risk_scores AS (
    SELECT
        drg.hadm_id,
        MAX(drg.drg_severity) AS drg_severity_score -- Using MAX in case of multiple DRGs per admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    GROUP BY
        drg.hadm_id
),
-- Combine all relevant flags and scores for all age-matched admissions
all_cohort_data AS (
    SELECT
        ba.*,
        (ami.hadm_id IS NOT NULL) AS has_ami_diagnosis,
        (icu.hadm_id IS NOT NULL) AS has_icu_stay,
        (comp.hadm_id IS NOT NULL) AS has_major_complication,
        drs.drg_severity_score AS risk_score_proxy
    FROM
        base_admissions ba
    LEFT JOIN
        admissions_with_ami ami
        ON ba.hadm_id = ami.hadm_id
    LEFT JOIN
        admissions_with_icu icu
        ON ba.hadm_id = icu.hadm_id
    LEFT JOIN
        admissions_with_major_complication comp
        ON ba.hadm_id = comp.hadm_id
    LEFT JOIN
        drg_risk_scores drs
        ON ba.hadm_id = drs.hadm_id
),
-- Group A: Females, 68-78, AMI, ICU stay
group_a AS (
    SELECT *
    FROM all_cohort_data
    WHERE
        gender = 'F'
        AND has_ami_diagnosis
        AND has_icu_stay
),
-- Group B: Age-matched general inpatients (68-78, all genders, all diagnoses)
group_b AS (
    SELECT *
    FROM all_cohort_data
    -- Age filter already applied in base_admissions CTE
),
-- Calculate median and IQR for Group A's risk score
group_a_risk_score_summary AS (
    SELECT
        APPROX_QUANTILES(risk_score_proxy, 100)[OFFSET(50)] AS median_risk_score,
        APPROX_QUANTILES(risk_score_proxy, 100)[OFFSET(25)] AS q1_risk_score,
        APPROX_QUANTILES(risk_score_proxy, 100)[OFFSET(75)] AS q3_risk_score
    FROM group_a
    WHERE risk_score_proxy IS NOT NULL
),
-- Get the median risk score of Group A for percentile comparison
median_risk_score_for_group_a AS (
    SELECT median_risk_score FROM group_a_risk_score_summary
),
-- Calculate the percentile rank of Group A's median risk score within Group B's risk scores
risk_percentile_a_in_b AS (
    SELECT
        (COUNT(CASE WHEN gb.risk_score_proxy <= mra.median_risk_score THEN 1 END) * 100.0 / COUNT(gb.risk_score_proxy)) AS percentile_rank
    FROM group_b gb, median_risk_score_for_group_a mra
    WHERE gb.risk_score_proxy IS NOT NULL
)

-- Final SELECT statement to present all requested metrics
SELECT
    'Group A: Females, 68-78, AMI, ICU Stay' AS cohort_a_description,
    (SELECT COUNT(DISTINCT ga.hadm_id) FROM group_a ga) AS group_a_n_admissions,
    (SELECT SAFE_DIVIDE(COUNTIF(ga.is_90_day_mortality_flag), COUNT(DISTINCT ga.hadm_id)) FROM group_a ga) AS group_a_90_day_mortality_rate,
    (SELECT grp.median_risk_score FROM group_a_risk_score_summary grp) AS group_a_median_risk_score,
    (SELECT grp.q1_risk_score FROM group_a_risk_score_summary grp) AS group_a_risk_score_q1,
    (SELECT grp.q3_risk_score FROM group_a_risk_score_summary grp) AS group_a_risk_score_q3,
    (SELECT SAFE_DIVIDE(COUNTIF(ga.has_major_complication), COUNT(DISTINCT ga.hadm_id)) FROM group_a ga) AS group_a_major_complication_rate,
    (SELECT APPROX_QUANTILES(ga.los_hospital_days, 100)[OFFSET(50)] FROM group_a ga WHERE ga.is_90_day_survivor_flag AND ga.los_hospital_days IS NOT NULL) AS group_a_survivor_median_los_days,
    (SELECT APPROX_QUANTILES(ga.los_hospital_days, 100)[OFFSET(25)] FROM group_a ga WHERE ga.is_90_day_survivor_flag AND ga.los_hospital_days IS NOT NULL) AS group_a_survivor_los_q1,
    (SELECT APPROX_QUANTILES(ga.los_hospital_days, 100)[OFFSET(75)] FROM group_a ga WHERE ga.is_90_day_survivor_flag AND ga.los_hospital_days IS NOT NULL) AS group_a_survivor_los_q3,

    'Group B: Age-matched General Inpatients (68-78)' AS cohort_b_description,
    (SELECT COUNT(DISTINCT gb.hadm_id) FROM group_b gb) AS group_b_n_admissions,
    (SELECT SAFE_DIVIDE(COUNTIF(gb.has_major_complication), COUNT(DISTINCT gb.hadm_id)) FROM group_b gb) AS group_b_major_complication_rate,
    (SELECT APPROX_QUANTILES(gb.los_hospital_days, 100)[OFFSET(50)] FROM group_b gb WHERE gb.is_90_day_survivor_flag AND gb.los_hospital_days IS NOT NULL) AS group_b_survivor_median_los_days,
    (SELECT APPROX_QUANTILES(gb.los_hospital_days, 100)[OFFSET(25)] FROM group_b gb WHERE gb.is_90_day_survivor_flag AND gb.los_hospital_days IS NOT NULL) AS group_b_survivor_los_q1,
    (SELECT APPROX_QUANTILES(gb.los_hospital_days, 100)[OFFSET(75)] FROM group_b gb WHERE gb.is_90_day_survivor_flag AND gb.los_hospital_days IS NOT NULL) AS group_b_survivor_los_q3,

    (SELECT rp.percentile_rank FROM risk_percentile_a_in_b rp) AS group_a_median_risk_score_percentile_in_group_b;