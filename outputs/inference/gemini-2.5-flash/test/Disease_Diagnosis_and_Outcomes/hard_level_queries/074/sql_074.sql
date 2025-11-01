WITH patient_cohort AS (
    -- 1. Identify male inpatients aged 79-89 with PE
    SELECT DISTINCT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        p.dod
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 79 AND 89
        -- PE ICD-10: I26%, ICD-9: 415.1%
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
            OR (di.icd_version = 9 AND di.icd_code LIKE '415.1%')
        )
),
comorbidity_flags AS (
    -- 2. Identify common comorbidities using ICD codes (a proxy for Elixhauser categories for comorbidity burden)
    SELECT
        pc.subject_id,
        pc.hadm_id,
        MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'I50%' THEN 1
                 WHEN di.icd_version = 9 AND di.icd_code LIKE '428%' THEN 1 ELSE 0 END) AS has_chf,
        MAX(CASE WHEN di.icd_version = 10 AND (di.icd_code LIKE 'J44%' OR di.icd_code LIKE 'J45%') THEN 1
                 WHEN di.icd_version = 9 AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code LIKE '493%') THEN 1 ELSE 0 END) AS has_copd,
        MAX(CASE WHEN di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%') THEN 1
                 WHEN di.icd_version = 9 AND (di.icd_code LIKE '250%') THEN 1 ELSE 0 END) AS has_diabetes,
        MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N18%' THEN 1
                 WHEN di.icd_version = 9 AND di.icd_code LIKE '585%' THEN 1 ELSE 0 END) AS has_renal_failure,
        MAX(CASE WHEN di.icd_version = 10 AND di.icd_code BETWEEN 'C00' AND 'C96' THEN 1
                 WHEN di.icd_version = 9 AND di.icd_code BETWEEN '140' AND '208' THEN 1 ELSE 0 END) AS has_malignancy,
        MAX(CASE WHEN di.icd_version = 10 AND (di.icd_code LIKE 'K70%' OR di.icd_code LIKE 'K71%' OR di.icd_code LIKE 'K73%' OR di.icd_code LIKE 'K74%') THEN 1
                 WHEN di.icd_version = 9 AND (di.icd_code LIKE '571%' OR di.icd_code LIKE '572%' OR di.icd_code LIKE '573%') THEN 1 ELSE 0 END) AS has_liver_disease
    FROM
        patient_cohort pc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON pc.hadm_id = di.hadm_id
    GROUP BY
        pc.subject_id, pc.hadm_id
),
comorbidity_scores AS (
    -- Sum up comorbidity flags to get a burden score (our proxy for "composite risk score")
    SELECT
        subject_id,
        hadm_id,
        (has_chf + has_copd + has_diabetes + has_renal_failure + has_malignancy + has_liver_disease) AS comorbidity_score
    FROM
        comorbidity_flags
),
ranked_comorbidity_scores AS (
    -- Rank patients by comorbidity score and identify the top quartile (highest scores)
    SELECT
        cs.subject_id,
        cs.hadm_id,
        cs.comorbidity_score,
        NTILE(4) OVER (ORDER BY cs.comorbidity_score DESC) AS comorbidity_quartile
    FROM
        comorbidity_scores cs
),
final_pe_cohort AS (
    -- Filter for the top-quartile comorbidity burden
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.admittime,
        pc.deathtime, -- in-hospital deathtime
        pc.dod,      -- patient overall date of death
        rcs.comorbidity_score
    FROM
        patient_cohort pc
    INNER JOIN
        ranked_comorbidity_scores rcs
        ON pc.subject_id = rcs.subject_id AND pc.hadm_id = rcs.hadm_id
    WHERE
        rcs.comorbidity_quartile = 1 -- Selects the top 25% by comorbidity_score
),
cohort_metrics AS (
    -- Calculate mortality, complications, and survival days for each patient in the final cohort
    SELECT
        fpc.subject_id,
        fpc.hadm_id,
        fpc.comorbidity_score,
        -- 30-day mortality: `hospital_expire_flag` from admissions table, combined with `dod` for post-discharge mortality
        MAX(CASE WHEN a.hospital_expire_flag = 1 THEN 1
                 WHEN fpc.dod IS NOT NULL AND DATE_DIFF(fpc.dod, fpc.admittime, DAY) <= 30 THEN 1
                 ELSE 0 END) AS thirty_day_mortality_flag,
        -- Cardiac complications (examples)
        MAX(CASE WHEN di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I50%' OR di.icd_code LIKE 'I46%' OR di.icd_code LIKE 'I48%') THEN 1 -- MI, Heart Failure, Cardiac Arrest, Atrial Fibrillation
                 WHEN di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '428%' OR di.icd_code LIKE '427.5%' OR di.icd_code LIKE '427.3%') THEN 1
                 ELSE 0 END) AS cardiac_complication_flag,
        -- Neurologic complications (examples)
        MAX(CASE WHEN di.icd_version = 10 AND (di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'G40%' OR di.icd_code = 'G934') THEN 1 -- Stroke, Epilepsy, Encephalopathy (G93.4 as G934 in ICD-10)
                 WHEN di.icd_version = 9 AND (di.icd_code LIKE '434%' OR di.icd_code LIKE '345%' OR di.icd_code = '348.3') THEN 1 -- Stroke, Epilepsy, Encephalopathy (348.3 in ICD-9)
                 ELSE 0 END) AS neurologic_complication_flag,
        -- Survival days from admission to death, if death is recorded
        DATE_DIFF(fpc.dod, fpc.admittime, DAY) AS survival_days_if_died
    FROM
        final_pe_cohort fpc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a ON fpc.hadm_id = a.hadm_id -- To get hospital_expire_flag
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON fpc.hadm_id = di.hadm_id
    GROUP BY
        fpc.subject_id, fpc.hadm_id, fpc.comorbidity_score, fpc.dod, fpc.admittime
),
final_cohort_with_ranks AS (
    -- Calculate the percentile rank for each patient's comorbidity score within the cohort
    SELECT
        cm.*,
        PERCENT_RANK() OVER (ORDER BY cm.comorbidity_score ASC) AS comorbidity_score_percent_rank
    FROM
        cohort_metrics cm
)
-- Final aggregation to answer the question
SELECT
    -- Median Composite Risk Score Percentile for the cohort
    -- Calculates the median of the percentile ranks of comorbidity scores among the cohort
    PERCENTILE_CONT(fcr.comorbidity_score_percent_rank, 0.5) AS median_composite_risk_score_percentile,

    -- 30-day mortality rate (percentage)
    AVG(fcr.thirty_day_mortality_flag) * 100 AS thirty_day_mortality_rate_percent,

    -- Cardiac complication rate (percentage)
    AVG(fcr.cardiac_complication_flag) * 100 AS cardiac_complication_rate_percent,

    -- Neurologic complication rate (percentage)
    AVG(fcr.neurologic_complication_flag) * 100 AS neurologic_complication_rate_percent,

    -- Median survival days for those who died (only considering valid positive survival days)
    -- Using CASE to filter for non-negative survival days, PERCENTILE_CONT ignores NULLs
    PERCENTILE_CONT(CASE WHEN fcr.survival_days_if_died >= 0 THEN fcr.survival_days_if_died END, 0.5) AS median_survival_days
FROM
    final_cohort_with_ranks fcr;