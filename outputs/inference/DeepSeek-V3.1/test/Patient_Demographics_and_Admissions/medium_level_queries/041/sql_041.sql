WITH patient_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        p.anchor_age,
        p.gender,
        a.admission_type,
        a.discharge_location,
        a.hospital_expire_flag,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE
        p.anchor_age BETWEEN 88 AND 98
        AND p.gender = 'M'
        AND a.admission_type = 'ELECTIVE'
        AND a.dischtime > a.admittime  -- Ensure valid LOS
),
discharge_groups AS (
    SELECT
        hadm_id,
        los_days,
        CASE
            WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN discharge_location = 'HOME' THEN 'Home'
            WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'CHRONIC/LONG TERM ACUTE CARE') THEN 'SNF/rehab/LTACH'
            ELSE 'Other'  -- For completeness, though not requested
        END AS discharge_outcome
    FROM patient_cohort
)
SELECT
    discharge_outcome,
    COUNT(*) AS num_patients,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
    ROUND(COUNTIF(los_days <= 7) / COUNT(*) * 100, 2) AS pct_los_leq_7_days
FROM discharge_groups
WHERE discharge_outcome != 'Other'  -- Exclude ungrouped outcomes
GROUP BY discharge_outcome
ORDER BY discharge_outcome;