WITH first_service AS (
    SELECT 
        hadm_id,
        curr_service,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.services`
),
filtered_first_service AS (
    SELECT hadm_id
    FROM first_service
    WHERE rn = 1
        AND curr_service LIKE 'MED%'
)
SELECT
    discharge_category,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median_los,
    APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75_los,
    APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90_los,
    COUNTIF(los <= 7) * 100.0 / COUNT(*) AS percentile_rank_7
FROM (
    SELECT
        a.hadm_id,
        a.hospital_expire_flag,
        a.discharge_location,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
        CASE 
            WHEN a.hospital_expire_flag = 1 THEN 'in_hospital_death'
            WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
            ELSE 'facility'
        END AS discharge_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN filtered_first_service fs
        ON a.hadm_id = fs.hadm_id
    WHERE 
        p.gender = 'F'
        AND a.admission_type IN ('EMERGENCY', 'URGENT')
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 52 AND 62
) sub
GROUP BY discharge_category;