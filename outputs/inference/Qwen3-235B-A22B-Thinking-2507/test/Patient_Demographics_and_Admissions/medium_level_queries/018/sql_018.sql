WITH base AS (
    SELECT
        a.hadm_id,
        -- Compute age at admission
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        -- Compute LOS in days (as fractional)
        DATETIME_DIFF(a.dischtime, a.admittime, MINUTE) / (24*60.0) AS los_days,
        -- Define discharge group
        CASE 
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN a.discharge_location = 'HOME' THEN 'Home'
            ELSE 'Facility'
        END AS discharge_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND a.admission_location = 'TRANSFER FROM HOSPITAL'
        AND a.dischtime IS NOT NULL
        -- Filter by age: 43 to 53 inclusive
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),
group_stats AS (
    SELECT
        discharge_group,
        APPROX_QUANTILES(los_days, 1000) AS quantiles
    FROM base
    GROUP BY discharge_group
),
quantiles_expanded AS (
    SELECT
        discharge_group,
        quantiles[OFFSET(250)] AS q1,
        quantiles[OFFSET(500)] AS median_los,
        quantiles[OFFSET(750)] AS q3
    FROM group_stats
),
percent_le_10 AS (
    SELECT
        discharge_group,
        COUNTIF(los_days <= 10) * 100.0 / COUNT(*) AS percent_los_le_10
    FROM base
    GROUP BY discharge_group
),
all_groups AS (
    SELECT 'Home' AS discharge_group
    UNION ALL
    SELECT 'Facility'
    UNION ALL
    SELECT 'In-hospital death'
)
SELECT
    g.discharge_group,
    q.median_los,
    q.q3 - q.q1 AS iqr,
    p.percent_los_le_10
FROM all_groups g
LEFT JOIN quantiles_expanded q ON g.discharge_group = q.discharge_group
LEFT JOIN percent_le_10 p ON g.discharge_group = p.discharge_group
ORDER BY 
    CASE g.discharge_group
        WHEN 'Home' THEN 1
        WHEN 'Facility' THEN 2
        WHEN 'In-hospital death' THEN 3
    END;