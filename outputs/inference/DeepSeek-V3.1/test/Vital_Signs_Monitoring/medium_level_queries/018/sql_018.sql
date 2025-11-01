WITH cohort AS (
    SELECT 
        ie.stay_id,
        ie.intime,
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 75 AND 85
), sbp_events AS (
    SELECT 
        c.stay_id,
        c.intime,
        ce.charttime,
        ce.valuenum AS sbp
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid IN (220050, 220179)  -- SBP itemids: Arterial and NIBP
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= c.intime
        AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
), per_stay_mean AS (
    SELECT
        stay_id,
        AVG(sbp) AS mean_sbp
    FROM sbp_events
    GROUP BY stay_id
    HAVING COUNT(*) > 0  -- ensure at least one measurement
)
SELECT 
    COUNTIF(mean_sbp <= 140) * 100.0 / COUNT(*) AS percentile
FROM per_stay_mean;