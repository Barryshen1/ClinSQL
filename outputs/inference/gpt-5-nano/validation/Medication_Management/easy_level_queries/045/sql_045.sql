WITH aspirin AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.starttime AS starttime,
    p.stoptime AS stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE LOWER(p.drug) LIKE '%aspirin%'
    AND p.starttime IS NOT NULL
),

-- Define P2Y12 inhibitor intervals
p2y12 AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.starttime AS starttime,
    p.stoptime AS stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE (
      LOWER(p.drug) LIKE '%clopidogrel%'
      OR LOWER(p.drug) LIKE '%prasugrel%'
      OR LOWER(p.drug) LIKE '%ticagrelor%'
  )
  AND p.starttime IS NOT NULL
),

-- Compute overlaps between aspirin and P2Y12 intervals within the same admission
overlaps AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    GREATEST(a.starttime, b.starttime) AS overlap_start,
    LEAST(a.stoptime, b.stoptime) AS overlap_end
  FROM aspirin AS a
  JOIN p2y12 AS b
    ON a.subject_id = b.subject_id
   AND a.hadm_id = b.hadm_id
   -- Overlap must be positive
   WHERE LEAST(a.stoptime, b.stoptime) > GREATEST(a.starttime, b.starttime)
),

-- Duration of each DAPT overlap segment (in seconds)
durations AS (
  SELECT
    o.subject_id,
    o.hadm_id,
    TIMESTAMP_DIFF(o.overlap_end, o.overlap_start, SECOND) AS duration_seconds
  FROM overlaps AS o
  WHERE TIMESTAMP_DIFF(o.overlap_end, o.overlap_start, SECOND) > 0
),

-- Cohort: male patients aged 57-67
cohort AS (
  SELECT DISTINCT adm.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'Male'
    AND pat.anchor_age BETWEEN 57 AND 67
)

-- Final: compute IQR (Q1 and Q3) of DAPT durations in hours
SELECT
  PERCENTILE_CONT(duration_hours, 0.25) OVER() AS q1_hours,
  PERCENTILE_CONT(duration_hours, 0.75) OVER() AS q3_hours
FROM (
  SELECT duration_seconds / 3600.0 AS duration_hours
  FROM durations d
  JOIN cohort c ON d.subject_id = c.subject_id
) t
LIMIT 1;