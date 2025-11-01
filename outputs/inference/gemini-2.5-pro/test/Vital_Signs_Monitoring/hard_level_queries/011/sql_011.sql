WITH
-- Step 1: Identify the cohort of female ICU patients aged 55-65 with pneumonia
cohort AS (
    SELECT DISTINCT
        p.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.los
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS i
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON i.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON i.hadm_id = dx.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) BETWEEN 55 AND 65 -- Age at ICU admission
        AND LOWER(d_dx.long_title) LIKE '%pneumonia%'
),

-- Step 2: Calculate the instability score for each patient in the cohort.
-- The score is the count of abnormal vital signs in the first 24 hours of the ICU stay.
instability_scores AS (
    SELECT
        c.stay_id,
        COUNT(ce.itemid) AS instability_score
    FROM
        cohort AS c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON c.stay_id = ce.stay_id
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL
        AND (
            (ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100)) -- Heart Rate
            OR (ce.itemid = 220052 AND ce.valuenum < 65) -- Mean Arterial Pressure
            OR (ce.itemid = 220210 AND (ce.valuenum < 12 OR ce.valuenum > 25)) -- Respiratory Rate
            OR (ce.itemid = 220277 AND ce.valuenum < 92) -- SpO2
        )
    GROUP BY
        c.stay_id
),

-- Step 3: Combine scores with cohort data and rank into deciles
ranked_scores AS (
    SELECT
        s.stay_id,
        c.hadm_id,
        c.los,
        s.instability_score,
        NTILE(10) OVER (ORDER BY s.instability_score DESC) as decile
    FROM
        instability_scores AS s
    INNER JOIN
        cohort AS c ON s.stay_id = c.stay_id
),

-- Step 4: Calculate the percentile for a score of 60
percentile_calc AS (
    SELECT
        100.0 * COUNTIF(instability_score < 60) / COUNT(*) AS percentile_of_score_60
    FROM
        instability_scores
),

-- Step 5: Calculate outcomes for the most unstable decile (decile = 1)
top_decile_outcomes AS (
    SELECT
        AVG(rs.los) AS avg_los,
        100.0 * AVG(CAST(adm.hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM
        ranked_scores AS rs
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON rs.hadm_id = adm.hadm_id
    WHERE
        rs.decile = 1
)

-- Final Step: Combine results into a single output table
SELECT
    'Percentile of score 60' AS metric,
    ROUND(percentile_of_score_60, 2) AS value
FROM
    percentile_calc

UNION ALL

SELECT
    'Avg ICU LOS for most unstable decile (days)' AS metric,
    ROUND(avg_los, 2) AS value
FROM
    top_decile_outcomes

UNION ALL

SELECT
    'Mortality for most unstable decile (%)' AS metric,
    ROUND(mortality_rate, 2) AS value
FROM
    top_decile_outcomes;