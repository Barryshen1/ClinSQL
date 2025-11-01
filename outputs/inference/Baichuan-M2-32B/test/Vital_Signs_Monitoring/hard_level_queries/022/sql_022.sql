WITH arf_icd_codes AS (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE 
        (icd_version = 9 AND icd_code IN ('518.81', '518.82', '518.83', '518.84'))
        OR
        (icd_version = 10 AND icd_code IN ('J96.9', 'J98.4', 'J98.5', 'J98.6', 'J98.7', 'J98.8', 'J98.9'))
),
eligible_icu_stays AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.los,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
    INNER JOIN arf_icd_codes arf
        ON d.icd_code = arf.icd_code
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 85 AND 95
        AND i.first_careunit IS NOT NULL  -- Ensure it's a valid ICU stay
),
vital_sign_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE 
        category IN ('Heart rate', 'Blood pressure systolic', 'Respiratory rate')
        AND linksto = 'chartevents'
),
vital_sign_data AS (
    SELECT 
        c.stay_id,
        c.itemid,
        c.charttime,
        c.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    INNER JOIN vital_sign_items v
        ON c.itemid = v.itemid
    WHERE 
        c.valuenum IS NOT NULL
        AND c.valuenum != 0  -- Exclude zero values which might be errors
),
first_24h_vitals AS (
    SELECT 
        e.stay_id,
        e.itemid,
        e.charttime,
        e.valuenum,
        -- Calculate time offset from ICU admission
        TIMESTAMP_DIFF(e.charttime, i.intime, MINUTE) AS time_offset_minutes
    FROM vital_sign_data e
    INNER JOIN eligible_icu_stays i
        ON e.stay_id = i.stay_id
    WHERE 
        TIMESTAMP_DIFF(e.charttime, i.intime, MINUTE) BETWEEN 0 AND 1440  -- First 24 hours
),
vital_stats AS (
    SELECT 
        stay_id,
        itemid,
        -- Compute standard deviation per vital sign per stay
        STDDEV(valuenum) AS std_dev
    FROM first_24h_vitals
    GROUP BY stay_id, itemid
),
instability_scores AS (
    SELECT 
        stay_id,
        -- Average the standard deviations of the three vital signs
        AVG(std_dev) AS instability_score
    FROM vital_stats
    GROUP BY stay_id
),
all_scores AS (
    SELECT 
        i.stay_id,
        i.instability_score,
        e.los,
        e.hospital_expire_flag
    FROM instability_scores i
    INNER JOIN eligible_icu_stays e
        ON i.stay_id = e.stay_id
),
-- Calculate the percentile rank for score 85
percentile_calc AS (
    SELECT 
        instability_score,
        -- Use PERCENT_RANK to get the percentile for each score, then find the rank for 85
        PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank
    FROM all_scores
),
target_percentile AS (
    SELECT 
        -- We need the percentile rank for 85, but if 85 is not present, we interpolate?
        -- Instead, we can compute the cumulative distribution and find the percentile for 85
        -- Using APPROX_QUANTILES to get the distribution and then calculate the percentile
        APPROX_QUANTILES(instability_score, 100) AS quantiles
    FROM all_scores
),
-- For the most unstable quartile (top 25%)
quartile_groups AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
    FROM all_scores
),
most_unstable_quartile AS (
    SELECT 
        AVG(los) AS avg_los,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM quartile_groups
    WHERE quartile = 1  -- Top quartile (highest instability)
)
-- Final output: percentile rank of 85, and metrics for most unstable quartile
SELECT 
    (SELECT 
        -- Find the percentile for 85 by locating between which quantiles it falls
        -- We have 100 quantiles, so we can find the index where 85 falls
        -- This is a simplified approach; in practice, we might need to interpolate
        -- Alternatively, we can use the PERCENT_RANK method but we need to handle 85 not being in the data
        -- We'll use the quantiles array to find the percentile
        (SELECT 
            -- Find the first quantile index where the value >= 85
            MIN(quantile_index) 
        FROM 
            UNNEST((SELECT quantiles FROM target_percentile)) AS q WITH OFFSET AS quantile_index
        WHERE 
            q >= 85
        ) / 100.0 AS percentile_rank
    ) AS percentile_rank_85,
    (SELECT avg_los FROM most_unstable_quartile) AS avg_los_most_unstable,
    (SELECT mortality_rate FROM most_unstable_quartile) AS mortality_rate_most_unstable;