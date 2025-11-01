WITH
-- Step 1: Identify the base cohort of male patients, aged 79-89, with a PE diagnosis.
base_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        -- FIX: Corrected and robust age calculation
        (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission,
        a.admittime,
        p.dod
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        -- FIX: Use the corrected age calculation in the WHERE clause as well
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 79 AND 89
        AND EXISTS ( -- Efficiently check for a PE diagnosis
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
            WHERE dx.hadm_id = a.hadm_id
            AND (
                (dx.icd_version = 9 AND dx.icd_code LIKE '4151%') -- i.e. 415.1x
                OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I26%')
            )
        )
),

-- Step 2: Add Elixhauser comorbidity scores to the base cohort.
cohort_with_comorbidity AS (
    SELECT
        b.subject_id,
        b.hadm_id,
        b.age_at_admission,
        b.admittime,
        b.dod,
        e.elixhauser_vanwalraven,
        e.congestive_heart_failure,
        e.chronic_pulmonary,
        e.cancer
    FROM base_cohort AS b
    -- FIX: Corrected the dataset path. MIMIC-IV derived tables are in 'mimiciv_derived'.
    INNER JOIN `physionet-data.mimiciv_derived.elixhauser` AS e
        ON b.hadm_id = e.hadm_id
),

-- Step 3: Filter for the top quartile of comorbidity burden. This is the final analysis cohort.
analysis_cohort AS (
    SELECT
        *
    FROM (
        SELECT
            *,
            NTILE(4) OVER (ORDER BY elixhauser_vanwalraven DESC) as comorbidity_quartile
        FROM cohort_with_comorbidity
    )
    WHERE comorbidity_quartile = 1
),

-- Step 4a: Extract vital signs from the first 24 hours of admission.
first_day_vitals AS (
    SELECT
        ac.hadm_id,
        MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 110 THEN 1 ELSE 0 END) AS has_tachycardia,
        MAX(CASE WHEN ce.itemid IN (220179, 220050) AND ce.valuenum < 100 THEN 1 ELSE 0 END) AS has_hypotension,
        MAX(CASE WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS has_hypoxemia
    FROM analysis_cohort AS ac
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON ac.hadm_id = ce.hadm_id
    WHERE
        ce.charttime BETWEEN ac.admittime AND DATETIME_ADD(ac.admittime, INTERVAL 24 HOUR)
        AND ce.itemid IN (
            220045, -- Heart Rate
            220179, -- Non Invasive Blood Pressure systolic
            220050, -- Arterial Blood Pressure systolic
            220277  -- O2 saturation pulseoxymetry
        )
    GROUP BY ac.hadm_id
),

-- Step 4b: Identify cardiac and neurologic complications during the hospital stay.
complications AS (
    SELECT
        hadm_id,
        MAX(CASE
            WHEN (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code = '78551' OR icd_code = '4275'))
              OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code = 'R570' OR icd_code LIKE 'I46%'))
            THEN 1 ELSE 0
        END) AS has_cardiac_complication,
        MAX(CASE
            WHEN (icd_version = 9 AND (icd_code LIKE '433%' OR icd_code LIKE '434%' OR SUBSTR(icd_code, 1, 3) IN ('430', '431', '432') OR icd_code = '78039'))
              OR (icd_version = 10 AND (icd_code LIKE 'I63%' OR SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62') OR icd_code LIKE 'R56%'))
            THEN 1 ELSE 0
        END) AS has_neuro_complication
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM analysis_cohort)
    GROUP BY hadm_id
),

-- Step 5: Calculate the composite risk score and prepare data for final analysis.
final_cohort_data AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.age_at_admission,
        ac.admittime,
        ac.dod,
        (
            ac.congestive_heart_failure +
            ac.chronic_pulmonary +
            ac.cancer +
            COALESCE(fdv.has_tachycardia, 0) +
            COALESCE(fdv.has_hypotension, 0) +
            COALESCE(fdv.has_hypoxemia, 0)
        ) AS composite_risk_score,
        COALESCE(comp.has_cardiac_complication, 0) AS has_cardiac_complication,
        COALESCE(comp.has_neuro_complication, 0) AS has_neuro_complication
    FROM analysis_cohort AS ac
    LEFT JOIN first_day_vitals AS fdv
        ON ac.hadm_id = fdv.hadm_id
    LEFT JOIN complications AS comp
        ON ac.hadm_id = comp.hadm_id
),

-- Step 6: Calculate cohort-level aggregate statistics.
cohort_stats AS (
    SELECT
        -- FIX: Corrected mortality calculation using DATE_DIFF and consistent DATE casting
        AVG(CASE WHEN dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 30 THEN 1 ELSE 0 END) AS mortality_rate_30_day,
        AVG(has_cardiac_complication) AS cardiac_complication_rate,
        AVG(has_neuro_complication) AS neurologic_complication_rate,
        -- FIX: Corrected median survival calculation for deceased patients only
        APPROX_QUANTILES(
            CASE WHEN dod IS NOT NULL THEN DATE_DIFF(DATE(dod), DATE(admittime), DAY) END,
            2 IGNORE NULLS
        )[OFFSET(1)] AS median_survival_days_deceased
    FROM final_cohort_data
)

-- Final Step: Combine patient-specific data for the 84-year-old with cohort stats.
SELECT
    fcd.subject_id,
    fcd.hadm_id,
    fcd.age_at_admission,
    fcd.composite_risk_score,
    ROUND(PERCENT_RANK() OVER (ORDER BY fcd.composite_risk_score) * 100, 2) AS composite_risk_score_percentile,
    ROUND(cs.mortality_rate_30_day * 100, 2) AS cohort_30_day_mortality_rate_percent,
    ROUND(cs.cardiac_complication_rate * 100, 2) AS cohort_cardiac_complication_rate_percent,
    ROUND(cs.neurologic_complication_rate * 100, 2) AS cohort_neurologic_complication_rate_percent,
    cs.median_survival_days_deceased
FROM final_cohort_data AS fcd
CROSS JOIN cohort_stats AS cs
WHERE fcd.age_at_admission = 84
ORDER BY fcd.subject_id, fcd.hadm_id;