WITH PatientCohort AS (
    SELECT
        p.subject_id,
        ad.hadm_id,
        icu.stay_id,
        icu.intime,
        -- Calculate age at admission to the hospital
        p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ad.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 56 AND 66
),
RawMAP AS (
    SELECT
        pc.stay_id,
        ce.valuenum AS map_value,
        ce.charttime
    FROM
        PatientCohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON pc.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220052 -- itemid for Arterial Blood Pressure mean
        AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 -- Ensure valid numeric MAP values
        AND ce.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 48 HOUR)
),
StayMeanMAP AS (
    SELECT
        stay_id,
        AVG(map_value) AS mean_map_per_stay
    FROM
        RawMAP
    GROUP BY
        stay_id
),
-- New CTE to categorize each stay's mean MAP
CategorizedMAP AS (
    SELECT
        stay_id,
        mean_map_per_stay,
        CASE
            WHEN mean_map_per_stay < 65 THEN '<65 mmHg'
            WHEN mean_map_per_stay >= 65 AND mean_map_per_stay < 75 THEN '65-74 mmHg'
            WHEN mean_map_per_stay >= 75 AND mean_map_per_stay < 85 THEN '75-84 mmHg'
            WHEN mean_map_per_stay >= 85 THEN '>=85 mmHg'
            ELSE 'Unknown' -- Should not be reached with valuenum > 0 filter
        END AS map_category
    FROM
        StayMeanMAP
)
-- Final aggregation to get count, mean, median, IQR per category
SELECT
    map_category,
    COUNT(stay_id) AS stay_count,
    AVG(mean_map_per_stay) AS mean_map,
    APPROX_QUANTILES(mean_map_per_stay, 100)[OFFSET(50)] AS median_map, -- Median (50th percentile)
    (APPROX_QUANTILES(mean_map_per_stay, 100)[OFFSET(75)] - APPROX_QUANTILES(mean_map_per_stay, 100)[OFFSET(25)]) AS iqr_map -- Interquartile Range (Q3 - Q1)
FROM
    CategorizedMAP
GROUP BY
    map_category
ORDER BY
    CASE map_category
        WHEN '<65 mmHg' THEN 1
        WHEN '65-74 mmHg' THEN 2
        WHEN '75-84 mmHg' THEN 3
        WHEN '>=85 mmHg' THEN 4
        ELSE 99
    END ASC;