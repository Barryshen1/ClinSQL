WITH icu_stays_filtered AS (
    SELECT 
        icu.stay_id,
        icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON icu.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 65 AND 75
),
bp_measurements AS (
    SELECT 
        ce.valuenum,
        CASE 
            WHEN ce.valuenum < 140 THEN '<140'
            WHEN ce.valuenum >= 140 AND ce.valuenum <= 159 THEN '140-159'
            WHEN ce.valuenum >= 160 THEN '>=160'
            ELSE NULL 
        END AS bp_category
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN icu_stays_filtered icu
        ON ce.stay_id = icu.stay_id
    WHERE 
        ce.charttime >= icu.intime
        AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (220050, 220179, 220180, 220181, 225309, 225310)
        AND ce.valuenum IS NOT NULL
)
SELECT 
    bp_category,
    AVG(valuenum) AS mean_bp,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_bp,
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_bp
FROM bp_measurements
WHERE bp_category IS NOT NULL
GROUP BY bp_category
ORDER BY 
    CASE bp_category
        WHEN '<140' THEN 1
        WHEN '140-159' THEN 2
        WHEN '>=160' THEN 3
    END;