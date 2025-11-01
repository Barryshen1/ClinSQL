WITH cohort_base AS (
    -- 1. Define the base cohort: Female patients, 48-58 years old at admission
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        -- Calculate age at admission
        EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
        -- Calculate hospital length of stay in days
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year + p.anchor_age) BETWEEN 48 AND 58
),
hemorrhagic_stroke_admissions AS (
    -- 2. Identify admissions with a diagnosis of hemorrhagic stroke
    SELECT DISTINCT
        di.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS di
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses AS d_icd
        ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
    WHERE
        (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'I61%') -- ICD-10 for Hemorrhagic Stroke (e.g., I61.x)
        OR (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '432.%') -- ICD-9 for Hemorrhagic Stroke (e.g., 432.x)
),
medications_48hr AS (
    -- 3. Get all medications prescribed within the first 48 hours of admission for the cohort
    SELECT
        cb.subject_id,
        cb.hadm_id,
        p.drug
    FROM
        cohort_base AS cb
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.prescriptions AS p
        ON cb.subject_id = p.subject_id AND cb.hadm_id = p.hadm_id
    WHERE
        p.starttime IS NOT NULL
        AND p.starttime >= cb.admittime
        AND p.starttime <= DATETIME_ADD(cb.admittime, INTERVAL 48 HOUR)
),
medication_summary AS (
    -- 4. Calculate medication complexity (total distinct meds) and serotonergic drug counts
    --    for each admission within the first 48 hours
    SELECT
        cb.subject_id,
        cb.hadm_id,
        cb.admittime,
        cb.dischtime,
        cb.los_days,
        cb.hospital_expire_flag,
        COUNT(DISTINCT m.drug) AS total_distinct_meds_48hr,
        COUNT(DISTINCT CASE
            -- Serotonergic drugs (illustrative list - a real study would use a more curated list)
            WHEN LOWER(m.drug) LIKE '%sertraline%'
            OR LOWER(m.drug) LIKE '%fluoxetine%'
            OR LOWER(m.drug) LIKE '%citalopram%'
            OR LOWER(m.drug) LIKE '%escitalopram%'
            OR LOWER(m.drug) LIKE '%paroxetine%'
            OR LOWER(m.drug) LIKE '%venlafaxine%'
            OR LOWER(m.drug) LIKE '%duloxetine%'
            OR LOWER(m.drug) LIKE '%trazodone%'
            OR LOWER(m.drug) LIKE '%ondansetron%' -- 5-HT3 antagonist, included as an example of 5-HT system related drug
            THEN m.drug
            ELSE NULL
        END) AS serotonergic_drugs_count_48hr
    FROM
        cohort_base AS cb
    LEFT JOIN
        medications_48hr AS m
        ON cb.hadm_id = m.hadm_id
    GROUP BY
        cb.subject_id, cb.hadm_id, cb.admittime, cb.dischtime, cb.los_days, cb.hospital_expire_flag
),
final_cohort_with_flags AS (
    -- 5. Join with hemorrhagic stroke flags and categorize by serotonergic drug count
    SELECT
        ms.subject_id,
        ms.hadm_id,
        ms.admittime,
        ms.dischtime,
        ms.los_days,
        ms.hospital_expire_flag,
        ms.total_distinct_meds_48hr,
        ms.serotonergic_drugs_count_48hr,
        CASE WHEN hsa.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_hemorrhagic_stroke,
        CASE
            WHEN ms.serotonergic_drugs_count_48hr >= 2 THEN '>=2 Serotonergic Drugs'
            ELSE '<2 Serotonergic Drugs'
        END AS serotonergic_drug_group
    FROM
        medication_summary AS ms
    LEFT JOIN
        hemorrhagic_stroke_admissions AS hsa
        ON ms.hadm_id = hsa.hadm_id
),
complexity_quartiles AS (
    -- 6. Assign complexity quartile based on total distinct medications for the entire cohort
    SELECT
        *,
        NTILE(4) OVER (ORDER BY total_distinct_meds_48hr DESC) AS complexity_quartile_desc -- 1 = highest complexity (top 25%), 4 = lowest
    FROM
        final_cohort_with_flags
)
-- Final SELECT statements for various comparisons

-- Comparison 1: Medication complexity distribution (mean, median, stddev) by hemorrhagic stroke status
SELECT
    'Medication Complexity Distribution (First 48 Hours)' AS analysis_type,
    CASE
        WHEN has_hemorrhagic_stroke = 1 THEN 'Hemorrhagic Stroke'
        ELSE 'Control (No Hemorrhagic Stroke)'
    END AS cohort_description,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    ROUND(AVG(total_distinct_meds_48hr), 2) AS avg_distinct_meds_48hr,
    APPROX_QUANTILES(total_distinct_meds_48hr, 100)[OFFSET(50)] AS median_distinct_meds_48hr, -- Median
    ROUND(STDDEV(total_distinct_meds_48hr), 2) AS stddev_distinct_meds_48hr,
    CAST(NULL AS FLOAT64) AS avg_los_days, -- Placeholder for alignment
    CAST(NULL AS FLOAT64) AS hospital_mortality_rate -- Placeholder for alignment
FROM
    complexity_quartiles
GROUP BY
    has_hemorrhagic_stroke

UNION ALL

-- Comparison 2: Outcomes (LOS, Mortality) for patients with >=2 serotonergic drugs vs <2, by hemorrhagic stroke status
SELECT
    'Outcomes by Serotonergic Drug Group' AS analysis_type,
    CASE
        WHEN has_hemorrhagic_stroke = 1 THEN 'Hemorrhagic Stroke - '
        ELSE 'Control (No Hemorrhagic Stroke) - '
    END || serotonergic_drug_group AS cohort_description,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    CAST(NULL AS FLOAT64) AS avg_distinct_meds_48hr, -- Placeholder for alignment
    CAST(NULL AS FLOAT64) AS median_distinct_meds_48hr,
    CAST(NULL AS FLOAT64) AS stddev_distinct_meds_48hr,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_rate -- As percentage
FROM
    complexity_quartiles
GROUP BY
    has_hemorrhagic_stroke,
    serotonergic_drug_group

UNION ALL

-- Comparison 3: Outcomes (LOS, Mortality) for the top complexity quartile (most distinct medications in 48 hours), by hemorrhagic stroke status
SELECT
    'Outcomes for Top Complexity Quartile' AS analysis_type,
    CASE
        WHEN has_hemorrhagic_stroke = 1 THEN 'Hemorrhagic Stroke - Top Complexity Quartile'
        ELSE 'Control (No Hemorrhagic Stroke) - Top Complexity Quartile'
    END AS cohort_description,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    CAST(NULL AS FLOAT64) AS avg_distinct_meds_48hr, -- Placeholder for alignment
    CAST(NULL AS FLOAT64) AS median_distinct_meds_48hr,
    CAST(NULL AS FLOAT64) AS stddev_distinct_meds_48hr,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS hospital_mortality_rate -- As percentage
FROM
    complexity_quartiles
WHERE
    complexity_quartile_desc = 1 -- Selects the top 25% most complex patients
GROUP BY
    has_hemorrhagic_stroke
ORDER BY
    analysis_type, cohort_description;