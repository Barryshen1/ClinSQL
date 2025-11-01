WITH
-- Step 1: Define the base cohort of male patients aged 39-49 at admission
base_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.dod
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
            ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 39 AND 49
),

-- Step 2: Identify relevant diagnoses (DKA, complications) and calculate a risk score proxy for each admission
diagnoses_by_hadm AS (
    SELECT
        hadm_id,
        -- Flag for DKA diagnosis
        MAX(CASE
            WHEN (icd_version = 9 AND icd_code LIKE '2501%')  -- Diabetes with ketoacidosis
              OR (icd_version = 10 AND icd_code IN ('E1010', 'E1110', 'E1210', 'E1310', 'E1410')) -- Type 1/2/other DM with ketoacidosis
            THEN 1
            ELSE 0
        END) AS is_dka,
        -- Flag for cardiovascular complication (Acute Myocardial Infarction)
        MAX(CASE
            WHEN (icd_version = 9 AND icd_code LIKE '410%') -- AMI
              OR (icd_version = 10 AND icd_code LIKE 'I21%')  -- AMI
            THEN 1
            ELSE 0
        END) AS has_cardio_complication,
        -- Flag for neurologic complication (Ischemic Stroke)
        MAX(CASE
            WHEN (icd_version = 9 AND icd_code LIKE '434%') -- Occlusion of cerebral arteries
              OR (icd_version = 10 AND icd_code LIKE 'I63%')  -- Cerebral infarction
            THEN 1
            ELSE 0
        END) AS has_neuro_complication,
        -- Risk score proxy: count of unique diagnosis codes
        COUNT(DISTINCT icd_code) AS diagnosis_count_risk_score
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        hadm_id IN (SELECT hadm_id FROM base_cohort)
    GROUP BY
        hadm_id
),

-- Step 3: Combine cohort demographics with diagnosis flags and calculate outcomes per admission
cohort_w_outcomes AS (
    SELECT
        bc.hadm_id,
        diag.is_dka,
        diag.diagnosis_count_risk_score,
        COALESCE(diag.has_cardio_complication, 0) AS has_cardio_complication,
        COALESCE(diag.has_neuro_complication, 0) AS has_neuro_complication,
        -- 30-day mortality flag (1 if died within 30 days of admission, 0 otherwise)
        CASE
            WHEN bc.dod IS NOT NULL AND DATE_DIFF(CAST(bc.dod AS DATE), CAST(bc.admittime AS DATE), DAY) BETWEEN 0 AND 30
            THEN 1
            ELSE 0
        END AS is_dead_in_30_days,
        -- Length of stay in days
        ROUND(SAFE_DIVIDE(DATETIME_DIFF(bc.dischtime, bc.admittime, HOUR), 24), 2) AS los_days
    FROM
        base_cohort AS bc
    INNER JOIN -- Use INNER JOIN to ensure every patient in the final cohort has at least one diagnosis
        diagnoses_by_hadm AS diag
            ON bc.hadm_id = diag.hadm_id
),

-- Step 4: Calculate summary statistics for the DKA cohort
dka_group_stats AS (
    SELECT
        'DKA Males 39-49' AS comparison_group,
        AVG(c.diagnosis_count_risk_score) AS mean_risk_score,
        AVG(c.is_dead_in_30_days) AS thirty_day_mortality_rate,
        AVG(c.has_cardio_complication) AS cardio_complication_rate,
        AVG(c.has_neuro_complication) AS neuro_complication_rate,
        AVG(CASE WHEN c.is_dead_in_30_days = 0 THEN c.los_days END) AS mean_survivor_los,
        -- Calculate the median (50th percentile) risk score for this specific group
        (SELECT
            PERCENTILE_CONT(diagnosis_count_risk_score, 0.5) OVER()
         FROM cohort_w_outcomes
         WHERE is_dka = 1
         LIMIT 1) AS risk_score_50th_percentile
    FROM
        cohort_w_outcomes AS c
    WHERE
        c.is_dka = 1
),

-- Step 5: Calculate summary statistics for the general cohort (all males 39-49)
all_males_group_stats AS (
    SELECT
        'All Males 39-49' AS comparison_group,
        AVG(c.diagnosis_count_risk_score) AS mean_risk_score,
        AVG(c.is_dead_in_30_days) AS thirty_day_mortality_rate,
        AVG(c.has_cardio_complication) AS cardio_complication_rate,
        AVG(c.has_neuro_complication) AS neuro_complication_rate,
        AVG(CASE WHEN c.is_dead_in_30_days = 0 THEN c.los_days END) AS mean_survivor_los,
        -- Percentile is not applicable to the general group in this context, so set to NULL
        CAST(NULL AS FLOAT64) AS risk_score_50th_percentile
    FROM
        cohort_w_outcomes AS c
)

-- Step 6: Combine the two groups for the final report
SELECT * FROM dka_group_stats
UNION ALL
SELECT * FROM all_males_group_stats
ORDER BY
    comparison_group DESC;