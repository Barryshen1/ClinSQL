WITH filtered AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.deathtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS,
    CASE
      WHEN a.deathtime IS NOT NULL THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%facility%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.services` AS sv
    ON a.subject_id = sv.subject_id AND a.hadm_id = sv.hadm_id
  WHERE LOWER(p.gender) IN ('f','female')
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
    AND (a.admission_type IS NULL OR LOWER(a.admission_type) != 'elective')
    AND LOWER(sv.curr_service) LIKE '%medicine%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
base AS (
  SELECT *
  FROM filtered
  WHERE discharge_group IN ('Home','Facility','In-hospital death')
),
quantiles AS (
  SELECT discharge_group, APPROX_QUANTILES(LOS, 101) AS q
  FROM base
  GROUP BY discharge_group
),
quantiles_expanded AS (
  SELECT discharge_group,
         q[OFFSET(50)] AS p50,
         q[OFFSET(75)] AS p75,
         q[OFFSET(90)] AS p90
  FROM quantiles
)
SELECT
  b.discharge_group,
  AVG(b.LOS) AS mean_los_days,
  MAX(qx.p50) AS p50,
  MAX(qx.p75) AS p75,
  MAX(qx.p90) AS p90,
  100.0 * SUM(CASE WHEN b.LOS <= 7 THEN 1 ELSE 0 END) / COUNT(*) AS pct_le_7_days
FROM base b
JOIN quantiles_expanded qx ON b.discharge_group = qx.discharge_group
GROUP BY b.discharge_group
ORDER BY b.discharge_group;