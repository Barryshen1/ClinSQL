WITH troponin_t_itemid AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%Troponin T%'
    ORDER BY itemid
    LIMIT 1
),
-- Step 2: Calculate the 99th percentile ULN for Troponin T across all valid measurements in the entire dataset.
dataset_troponin_t_uln AS (
    SELECT
        -- APPROX_QUANTILES(column, N) returns an array of N+1 elements.
        -- For the 99th percentile, we need 100 buckets (0th to 100th percentile).
        -- The 99th percentile value is at index 99 (0-indexed).
        (APPROX_QUANTILES(le.valuenum, 100))[OFFSET(99)] AS ul_value
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        troponin_t_itemid ti ON le.itemid = ti.itemid
    WHERE
        le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.valuenum >= 0    -- Lab values typically non-negative
),
-- Step 3: Get the initial (earliest) Troponin T measurement for each unique patient admission.
initial_troponin_t AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum AS initial_troponin_t_valuenum,
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        troponin_t_itemid ti ON le.itemid = ti.itemid
    WHERE
        le.valuenum IS NOT NULL
        AND le.valuenum >= 0
),
filtered_initial_troponin_t AS (
    SELECT
        subject_id,
        hadm_id,
        initial_troponin_t_valuenum
    FROM
        initial_troponin_t
    WHERE rn = 1
),
-- Step 4: Define the cohort based on age, gender, and initial Troponin T exceeding the dataset's ULN.
cohort AS (
    SELECT
        p.subject_id,
        fit.initial_troponin_t_valuenum,
        dtu.ul_value AS dataset_99th_percentile_uln
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm ON p.subject_id = adm.subject_id
    INNER JOIN
        filtered_initial_troponin_t fit ON adm.subject_id = fit.subject_id AND adm.hadm_id = fit.hadm_id
    CROSS JOIN -- ULN is a single value, CROSS JOIN is appropriate to bring it into the cohort's scope.
        dataset_troponin_t_uln dtu
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 49 AND 59
        AND fit.initial_troponin_t_valuenum > dtu.ul_value
)
-- Step 5: Report the required statistics for the defined cohort.
SELECT
    COUNT(DISTINCT cohort.subject_id) AS cohort_size,
    ANY_VALUE(cohort.dataset_99th_percentile_uln) AS dataset_99th_percentile_ULN,
    -- Use APPROX_QUANTILES for p25, median (p50), and p75.
    -- APPROX_QUANTILES(column, N) for N=4 returns [min, p25, p50, p75, max]
    (APPROX_QUANTILES(cohort.initial_troponin_t_valuenum, 4))[OFFSET(1)] AS p25_troponin_t,
    (APPROX_QUANTILES(cohort.initial_troponin_t_valuenum, 4))[OFFSET(2)] AS median_troponin_t,
    (APPROX_QUANTILES(cohort.initial_troponin_t_valuenum, 4))[OFFSET(3)] AS p75_troponin_t,
    MIN(cohort.initial_troponin_t_valuenum) AS min_troponin_t,
    MAX(cohort.initial_troponin_t_valuenum) AS max_troponin_t
FROM
    cohort;