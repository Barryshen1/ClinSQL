WITH sbp_data AS (
    SELECT
        p.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ie.intime AS icu_intime,
        c.charttime,
        c.valuenum AS sbp_value,
        (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) AS age_at_icu_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON p.subject_id = ie.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` c
        ON ie.subject_id = c.subject_id
        AND ie.hadm_id = c.hadm_id
        AND ie.stay_id = c.stay_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 65 AND 75
        AND c.itemid IN (
            220050, -- Arterial Blood Pressure Systolic
            220179  -- Non Invasive Blood Pressure Systolic
        )
        AND c.valuenum IS NOT NULL
        AND c.valuenum BETWEEN 20 AND 300 -- Filter for clinically plausible SBP values
        AND c.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
)
SELECT
    CASE
        WHEN sbp_value < 140 THEN '< 140'
        WHEN sbp_value BETWEEN 140 AND 159 THEN '140 - 159'
        WHEN sbp_value >= 160 THEN '>= 160'
        -- No ELSE needed as the WHERE clause and WHEN statements cover all possibilities
    END AS sbp_category,
    COUNT(sbp_value) AS total_measurements,
    ROUND(AVG(sbp_value), 2) AS mean_sbp,
    -- Using APPROX_QUANTILES for median (0.5) and IQR (Q3 - Q1)
    ROUND(APPROX_QUANTILES(sbp_value, 2)[OFFSET(1)], 2) AS median_sbp,
    ROUND(APPROX_QUANTILES(sbp_value, 4)[OFFSET(3)] - APPROX_QUANTILES(sbp_value, 4)[OFFSET(1)], 2) AS iqr_sbp
FROM
    sbp_data
GROUP BY
    sbp_category
ORDER BY
    sbp_category;