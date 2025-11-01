WITH InitialServices AS (
    -- Find the initial service type for each admission
    SELECT
        s.hadm_id,
        s.curr_service,
        ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY s.transfertime ASC) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.services` AS s
),
CohortData AS (
    -- Select the relevant cohort and calculate LOS and outcome
    SELECT
        adm.hadm_id,
        -- Calculate length of stay in days, ensuring float division
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, MINUTE) / (60 * 24.0) AS los_days,
        -- Determine patient outcome
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Death'
            ELSE 'Discharged Alive'
        END AS outcome
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    JOIN
        InitialServices AS iserv
        ON adm.hadm_id = iserv.hadm_id
    WHERE
        p.gender = 'M' -- Male patients
        AND p.anchor_age BETWEEN 57 AND 67 -- Aged 57-67
        AND adm.admission_type IN ('URGENT', 'EMERGENCY') -- Non-elective admissions
        AND iserv.rn = 1 -- Select the initial service for the admission
        AND iserv.curr_service = 'MED' -- Medicine inpatients
        AND adm.dischtime IS NOT NULL -- Ensure discharge time exists for LOS calculation
        AND adm.admittime IS NOT NULL -- Ensure admission time exists for LOS calculation
        AND adm.dischtime > adm.admittime -- Ensure valid LOS (discharge after admission)
),
OutcomeAggregates AS (
    -- Calculate mean, median (p50), p75, p90 LOS by outcome
    SELECT
        outcome,
        AVG(los_days) AS mean_los,
        -- Use APPROX_QUANTILES for BigQuery's approximate percentiles, accessing via OFFSET
        APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_p50,
        APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
        APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los
    FROM
        CohortData
    GROUP BY
        outcome
),
FiveDayStayPercentile AS (
    -- Calculate the percentile rank of a 5-day stay for the entire cohort
    SELECT
        100.0 * COUNTIF(los_days <= 5.0) / COUNT(los_days) AS percentile_rank_5day_stay
    FROM
        CohortData
)
-- Final selection combining the aggregated results and the overall percentile rank
SELECT
    oa.outcome,
    oa.mean_los,
    oa.median_los_p50,
    oa.p75_los,
    oa.p90_los,
    -- Include the single calculated percentile rank for a 5-day stay
    -- It will be the same for both outcome rows as it's computed over the entire cohort
    (SELECT percentile_rank_5day_stay FROM FiveDayStayPercentile) AS percentile_rank_5day_stay_overall_cohort
FROM
    OutcomeAggregates AS oa
ORDER BY
    oa.outcome;