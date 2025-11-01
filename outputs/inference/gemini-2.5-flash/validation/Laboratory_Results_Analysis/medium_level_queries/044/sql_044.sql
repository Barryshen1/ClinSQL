WITH admissions_cohort AS (
    -- Step 1: Filter for male patients aged 54-64 at admission
    SELECT
        pa.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 54 AND 64
),
troponin_t_itemid AS (
    -- Step 2: Identify the itemid for Troponin-T
    SELECT
        itemid
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
        LOWER(label) LIKE '%troponin t%'
        AND fluid = 'Blood' -- Added for more specificity if other 'Troponin T' labels exist
        AND category = 'Chemistry' -- Troponin T is typically found in the Chemistry category
),
initial_troponin_values AS (
    -- Step 3 & 4: Get the initial Troponin-T value for each admission in the cohort
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum AS troponin_t_initial_value
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        admissions_cohort ac
        ON le.subject_id = ac.subject_id AND le.hadm_id = ac.hadm_id
    INNER JOIN
        troponin_t_itemid tti
        ON le.itemid = tti.itemid
    WHERE
        le.valuenum IS NOT NULL -- Ensure only valid numeric results are considered
        AND le.valuenum >= 0     -- Troponin-T values should generally be non-negative
        AND le.valueuom = 'ng/mL' -- Ensure consistent units as per the question
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) = 1
),
filtered_cohort_with_troponin AS (
    -- Step 5: Apply the initial Troponin-T threshold
    SELECT
        itv.subject_id,
        itv.hadm_id,
        itv.troponin_t_initial_value
    FROM
        initial_troponin_values itv
    WHERE
        itv.troponin_t_initial_value > 0.01
)
-- Step 6: Calculate the required statistics for the filtered cohort
SELECT
    COUNT(*) AS n,
    ROUND(AVG(troponin_t_initial_value), 4) AS mean_troponin_t,
    ROUND(STDDEV(troponin_t_initial_value), 4) AS sd_troponin_t,
    ROUND(MIN(troponin_t_initial_value), 4) AS min_troponin_t,
    ROUND(MAX(troponin_t_initial_value), 4) AS max_troponin_t,
    ROUND(PERCENTILE_CONT(0.25, troponin_t_initial_value), 4) AS percentile_25,
    ROUND(PERCENTILE_CONT(0.50, troponin_t_initial_value), 4) AS median_troponin_t,
    ROUND(PERCENTILE_CONT(0.75, troponin_t_initial_value), 4) AS percentile_75
FROM
    filtered_cohort_with_troponin;