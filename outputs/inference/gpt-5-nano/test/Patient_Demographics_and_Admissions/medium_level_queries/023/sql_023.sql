WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.admission_type,
    a.edregtime,
    a.edouttime,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    (UPPER(a.admission_type) = 'EMERGENCY' OR a.edregtime IS NOT NULL)
    AND (p.anchor_age BETWEEN 41 AND 51)
    AND (LOWER(p.gender) = 'm')
    AND a.dischtime IS NOT NULL
),
los AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM base
  WHERE dischtime IS NOT NULL
),
categorized AS (
  SELECT
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN
        LOWER(discharge_location) LIKE '%facility%' OR
        LOWER(discharge_location) LIKE '%rehab%' OR
        LOWER(discharge_location) LIKE '%snf%' OR
        LOWER(discharge_location) LIKE '%nursing%' OR
        LOWER(discharge_location) LIKE '%long-term%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category,
    los_days
  FROM los
)
SELECT
  discharge_category
  , COUNT(*) AS n
  , SUM(CASE WHEN los_days >= 7.0 THEN 1 ELSE 0 END) AS n_ge7
  , SAFE_DIVIDE(
        SUM(CASE WHEN los_days >= 7.0 THEN 1 ELSE 0 END),
        COUNT(*)
    ) AS prop_ge7
  , SAFE_DIVIDE(
        SUM(CASE WHEN los_days <= 10.0 THEN 1 ELSE 0 END),
        COUNT(*)
    ) * 100.0 AS pctl_10day
FROM categorized
WHERE discharge_category IN ('Home','Facility','In-hospital death')
GROUP BY discharge_category
ORDER BY discharge_category;