WITH cohort_stays AS (
    -- Step 1 & 2: Identify all ICU stays for female patients aged 51-61
    SELECT
        icu.stay_id
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON icu.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON icu.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        -- Calculate age at admission and filter
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 51 AND 61
),
ranked_rr AS (
    -- Step 3: Find and rank the respiratory rate measurements for the cohort's ICU stays
    SELECT
        ce.valuenum,
        -- Rank measurements by time for each ICU stay to find the first one
        ROW_NUMBER() OVER(PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) as rn
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN
        cohort_stays ON ce.stay_id = cohort_stays.stay_id
    WHERE
        -- Filter for respiratory rate item IDs
        ce.itemid IN (
            220210, -- Respiratory Rate
            224690, -- Respiratory Rate (Total)
            224689  -- Respiratory Rate (spontaneous)
        )
        -- Filter for plausible, non-null numeric values
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum < 100
)
-- Step 4: Calculate the 25th percentile of the first respiratory rate measurements
SELECT
    DISTINCT PERCENTILE_CONT(rr.valuenum, 0.25) OVER() AS percentile_25_first_rr
FROM
    ranked_rr AS rr
WHERE
    rr.rn = 1; -- Only consider the first measurement for each stay;