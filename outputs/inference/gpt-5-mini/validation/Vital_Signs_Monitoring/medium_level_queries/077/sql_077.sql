WITH avg_hr_per_stay AS (
  -- compute per-stay average heart rate from chartevents (join to d_items to identify HR items)
  SELECT
    ce.stay_id,
    ce.hadm_id,
    ce.subject_id,
    AVG(ce.valuenum) AS avg_hr,
    COUNT(1) AS n_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  WHERE ce.stay_id IS NOT NULL
    AND ce.valuenum IS NOT NULL
    AND (
      LOWER(d.label) LIKE '%heart rate%'
      OR LOWER(d.label) LIKE '%pulse rate%'
      OR LOWER(d.label) LIKE '%pulse%'            -- capture items labeled "Pulse" (often heart rate)
      OR LOWER(d.abbreviation) = 'hr'
      OR LOWER(d.abbreviation) LIKE '%hr%'
      OR LOWER(d.unitname) LIKE '%/min%'          -- units in beats per minute
    )
  GROUP BY ce.stay_id, ce.hadm_id, ce.subject_id
)

SELECT
  COUNT(1) AS cohort_size,
  ROUND(100.0 * SUM(CASE WHEN avg_hr <= 90 THEN 1 ELSE 0 END) / COUNT(1), 2) AS percentile_of_90_pct
FROM `physionet-data.mimiciv_3_1_icu.icustays` s
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON s.subject_id = p.subject_id
JOIN avg_hr_per_stay h
  ON s.stay_id = h.stay_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 42 AND 52;