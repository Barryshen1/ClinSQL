WITH cohort AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.admission_type,
        a.hospital_expire_flag,
        a.discharge_location,
        DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date,
        TIMESTAMP_DIFF(a.admittime, DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
        `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
        a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND a.admission_type IN ('Emergency', 'Urgent')
        AND a.dischtime IS NOT NULL
        AND a.hospital_expire_flag IS NOT NULL
),
filtered_cohort AS (
    SELECT 
        *,
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
            WHEN discharge_location = 'Home' THEN 'home'
            ELSE 'facility'
        END AS outcome
    FROM cohort
    WHERE 
        age_at_admission BETWEEN 37 AND 47
)
SELECT 
    outcome,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25_los,
    APPROX_QUANTILES(los, 4)[OFFSET(2)] AS p50_los,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los,
    (SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS percentile_rank_7d
FROM filtered_cohort
GROUP BY outcome
ORDER BY outcome;