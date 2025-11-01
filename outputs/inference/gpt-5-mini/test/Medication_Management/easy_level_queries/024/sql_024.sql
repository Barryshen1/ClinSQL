WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
),

aspirin_presc AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    -- interval clipped to the admission
    GREATEST(COALESCE(pr.starttime, c.admittime), c.admittime) AS int_start,
    LEAST(COALESCE(pr.stoptime, c.dischtime), c.dischtime) AS int_end
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c
    ON pr.subject_id = c.subject_id
    AND pr.hadm_id = c.hadm_id
  WHERE LOWER(pr.drug) LIKE '%aspirin%'
),

p2y12_presc AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    GREATEST(COALESCE(pr.starttime, c.admittime), c.admittime) AS int_start,
    LEAST(COALESCE(pr.stoptime, c.dischtime), c.dischtime) AS int_end
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c
    ON pr.subject_id = c.subject_id
    AND pr.hadm_id = c.hadm_id
  WHERE (
    LOWER(pr.drug) LIKE '%clopidogrel%' OR LOWER(pr.drug) LIKE '%plavix%'
    OR LOWER(pr.drug) LIKE '%prasugrel%'  OR LOWER(pr.drug) LIKE '%effient%'
    OR LOWER(pr.drug) LIKE '%ticagrelor%' OR LOWER(pr.drug) LIKE '%brilinta%'
    OR LOWER(pr.drug) LIKE '%ticlopidine%' OR LOWER(pr.drug) LIKE '%ticlid%'
  )
),

-- keep only intervals that actually overlap the admission (positive length)
aspirin_intervals AS (
  SELECT * FROM aspirin_presc
  WHERE int_end > int_start
),

p2y12_intervals AS (
  SELECT * FROM p2y12_presc
  WHERE int_end > int_start
)

SELECT
  a.subject_id,
  a.hadm_id,
  a.drug AS aspirin_drug,
  p.drug AS p2y12_drug,
  GREATEST(a.int_start, p.int_start) AS overlap_start,
  LEAST(a.int_end, p.int_end) AS overlap_end,
  TIMESTAMP_DIFF(LEAST(a.int_end, p.int_end), GREATEST(a.int_start, p.int_start), SECOND) AS overlap_seconds,
  ROUND(TIMESTAMP_DIFF(LEAST(a.int_end, p.int_end), GREATEST(a.int_start, p.int_start), SECOND) / 86400.0, 2) AS overlap_days
FROM aspirin_intervals a
JOIN p2y12_intervals p
  ON a.hadm_id = p.hadm_id
  -- require a positive overlap between the two prescription intervals
  AND TIMESTAMP_DIFF(LEAST(a.int_end, p.int_end), GREATEST(a.int_start, p.int_start), SECOND) > 0
ORDER BY overlap_seconds DESC
LIMIT 1;