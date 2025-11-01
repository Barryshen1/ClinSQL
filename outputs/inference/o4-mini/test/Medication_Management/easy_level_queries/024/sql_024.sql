WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
),
-- Extract aspirin prescriptions
aspirin_rx AS (
  SELECT
    subject_id,
    hadm_id,
    starttime AS asp_start,
    stoptime  AS asp_stop
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    lower(drug) LIKE '%aspirin%'
    AND starttime IS NOT NULL
    AND stoptime  IS NOT NULL
),
-- Extract P2Y12 inhibitor prescriptions
p2y12_rx AS (
  SELECT
    subject_id,
    hadm_id,
    starttime AS pyr_start,
    stoptime  AS pyr_stop
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    -- clopidogrel, prasugrel, ticagrelor
    (
      lower(drug) LIKE '%clopidogrel%'
      OR lower(drug) LIKE '%prasugrel%'
      OR lower(drug) LIKE '%ticagrelor%'
    )
    AND starttime IS NOT NULL
    AND stoptime  IS NOT NULL
),
-- Compute DAPT overlap durations
dapt_overlaps AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- compute overlap interval
    GREATEST(a.asp_start, p.pyr_start) AS overlap_start,
    LEAST  (a.asp_stop,  p.pyr_stop ) AS overlap_end
  FROM
    cohort AS c
    JOIN aspirin_rx AS a
      ON c.subject_id = a.subject_id
     AND c.hadm_id    = a.hadm_id
    JOIN p2y12_rx AS p
      ON c.subject_id = p.subject_id
     AND c.hadm_id    = p.hadm_id
),
-- Filter valid overlaps and compute duration in days
dapt_durations AS (
  SELECT
    subject_id,
    hadm_id,
    overlap_start,
    overlap_end,
    -- duration in full days
    TIMESTAMP_DIFF(overlap_end, overlap_start, DAY) AS duration_days
  FROM
    dapt_overlaps
  WHERE
    overlap_end > overlap_start
)
-- Final: maximum single continuous DAPT duration
SELECT
  MAX(duration_days) AS max_dapt_duration_days
FROM
  dapt_durations;