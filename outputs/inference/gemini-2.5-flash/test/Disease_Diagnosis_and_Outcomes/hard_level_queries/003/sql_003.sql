WITH TargetCohortAdmissions AS (
    -- 1. Identify the specific cohort: Female, aged 70-80, with Pulmonary Embolism (PE)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.admission_type,
        -- Calculate age at admission
        -- The age calculation `anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)`
        -- works by effectively adjusting the anchor_age based on the difference
        -- between the admission year and the patient's anchor_year.
        p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 70 AND 80
        -- Filter for admissions with a PE diagnosis
        AND ad.hadm_id IN (
            SELECT DISTINCT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 10 AND icd_code LIKE 'I26%') -- ICD-10 codes for Pulmonary embolism
                OR (icd_version = 9 AND icd_code LIKE '4151%') -- ICD-9 codes for Pulmonary embolism
        )
),
ComorbidityAndOutcomeFlags AS (
    -- 2. Derive flags for comorbidities (for risk score) and specific outcomes (AKI, ARDS)
    SELECT
        tca.subject_id,
        tca.hadm_id,
        tca.admittime, -- Corrected typo from admitttime to admittime
        tca.dischtime,
        tca.deathtime,
        tca.admission_type,
        tca.age_at_admission,
        -- Comorbidity flags for custom risk score
        MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I50%') OR (d.icd_version = 9 AND d.icd_code LIKE '428%') THEN 1 ELSE 0 END) AS has_heart_failure,
        MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code BETWEEN 'N170' AND 'N199') OR (d.icd_version = 9 AND d.icd_code BETWEEN '5840' AND '5869') THEN 1 ELSE 0 END) AS has_renal_failure,
        MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code BETWEEN 'C00' AND 'D49') OR (d.icd_version = 9 AND d.icd_code BETWEEN '140' AND '239') THEN 1 ELSE 0 END) AS has_malignancy,
        -- Corrected ICD-9 syntax for stroke/TIA
        MAX(CASE WHEN (d.icd_version = 10 AND (d.icd_code BETWEEN 'I60' AND 'I69' OR d.icd_code LIKE 'G45%')) OR (d.icd_version = 9 AND LEFT(d.icd_code, 3) BETWEEN '430' AND '438') THEN 1 ELSE 0 END) AS has_stroke_or_tia,
        MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code BETWEEN 'E10' AND 'E14') OR (d.icd_version = 9 AND d.icd_code LIKE '250%') THEN 1 ELSE 0 END) AS has_diabetes,
        COUNT(DISTINCT d.icd_code) AS num_unique_diagnoses, -- For risk score
        -- Outcome flags for direct reporting
        MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'N17%') OR (d.icd_version = 9 AND d.icd_code LIKE '584%') THEN 1 ELSE 0 END) AS has_aki_diag,
        MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code = 'J80') OR (d.icd_version = 9 AND d.icd_code = '51882') THEN 1 ELSE 0 END) AS has_ards_diag
    FROM
        TargetCohortAdmissions AS tca
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        ON tca.subject_id = d.subject_id AND tca.hadm_id = d.hadm_id
    GROUP BY
        tca.subject_id, tca.hadm_id, tca.admittime, tca.dischtime, tca.deathtime, tca.admission_type, tca.age_at_admission
),
RiskScoreCalculation AS (
    -- 3. Calculate custom risk score and other admission-level metrics
    SELECT
        *,
        -- Custom simplified risk score calculation:
        -- - Emergency admission (2 points)
        -- - Each major comorbidity (1 point each)
        -- - Number of unique diagnoses (fractional, 0.1 per diagnosis)
        -- - Age within the 70-80 range (fractional, up to 1 point)
        (
            (CASE WHEN admission_type = 'EMERGENCY' THEN 2 ELSE 0 END) +
            has_heart_failure +
            has_renal_failure +
            has_malignancy +
            has_stroke_or_tia +
            has_diabetes +
            (num_unique_diagnoses * 0.1) +
            ((age_at_admission - 70) * 0.1) -- (70->0, 80->1)
        ) AS custom_risk_score,
        -- 90-day mortality flag
        (
            CASE
                WHEN deathtime IS NOT NULL AND DATE_DIFF(CAST(deathtime AS DATE), CAST(admittime AS DATE), DAY) <= 90 THEN 1
                ELSE 0
            END
        ) AS died_within_90_days,
        -- Length of Stay (LOS) in days
        DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) AS los_days
    FROM
      ComorbidityAndOutcomeFlags
),
RiskQuintiles AS (
    -- 4. Stratify into risk-score quintiles
    SELECT
        *,
        NTILE(5) OVER (ORDER BY custom_risk_score ASC) AS risk_quintile
    FROM
      RiskScoreCalculation
),
General70_80FemaleMortality AS (
    -- 5. Calculate general 70-80 female 90-day mortality for comparison
    SELECT
        COUNT(CASE WHEN ad.deathtime IS NOT NULL AND DATE_DIFF(CAST(ad.deathtime AS DATE), CAST(ad.admittime AS DATE), DAY) <= 90 THEN 1 END) * 100.0 / COUNT(ad.hadm_id) AS general_90_day_mortality_rate
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 70 AND 80
)
-- 6. Final aggregation and reporting per quintile
SELECT
    rq.risk_quintile,
    COUNT(rq.hadm_id) AS admissions_in_quintile,
    ROUND(MIN(rq.custom_risk_score), 2) AS min_risk_score_in_quintile,
    ROUND(MAX(rq.custom_risk_score), 2) AS max_risk_score_in_quintile,
    ROUND(AVG(rq.custom_risk_score), 2) AS avg_risk_score_in_quintile,
    -- 90-day mortality
    ROUND((SUM(rq.died_within_90_days) * 100.0 / COUNT(rq.hadm_id)), 2) AS mortality_rate_90_days_percentage,
    -- General 70-80 female 90-day mortality (from pre-calculated CTE)
    (SELECT general_90_day_mortality_rate FROM General70_80FemaleMortality) AS general_70_80_female_90_day_mort_pct,
    -- AKI rates
    ROUND((SUM(rq.has_aki_diag) * 100.0 / COUNT(rq.hadm_id)), 2) AS aki_rate_percentage,
    -- ARDS rates
    ROUND((SUM(rq.has_ards_diag) * 100.0 / COUNT(rq.hadm_id)), 2) AS ards_rate_percentage,
    -- Median survivor LOS
    APPROX_QUANTILES(
        CASE WHEN rq.died_within_90_days = 0 THEN rq.los_days ELSE NULL END,
        100
    )[OFFSET(50)] AS median_survivor_los_in_days
FROM
    RiskQuintiles AS rq
GROUP BY
    rq.risk_quintile
ORDER BY
    rq.risk_quintile;