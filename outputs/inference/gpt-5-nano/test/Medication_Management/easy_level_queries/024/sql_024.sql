WITH eligible_patients AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE (LOWER(gender) = 'm' OR LOWER(gender) = 'male')
    AND anchor_age BETWEEN 84 AND 94
),
aspirin AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime AS asp_start,
    p.stoptime AS asp_stop
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN eligible_patients e
    ON p.subject_id = e.subject_id
  WHERE LOWER(p.drug) LIKE '%aspirin%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
),
p2y12 AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime AS p2y_start,
    p.stoptime AS p2y_stop
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN eligible_patients e
    ON p.subject_id = e.subject_id
  WHERE (LOWER(p.drug) LIKE '%clopidogrel%'
         OR LOWER(p.drug) LIKE '%prasugrel%'
         OR LOWER(p.drug) LIKE '%ticagrelor%')
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
),
dapt_overlap AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- overlap duration in seconds
    TIMESTAMP_DIFF(GREATEST(a.asp_start, b.p2y_start),
                   LEAST(a.asp_stop, b.p2y_stop),
                   SECOND) AS overlap_seconds
  FROM aspirin a
  JOIN p2y12 b
    ON a.subject_id = b.subject_id
   AND a.hadm_id = b.hadm_id
  WHERE a.asp_stop > b.p2y_start
    AND b.p2y_stop > a.asp_start
)
SELECT
  MAX(overlap_seconds) / 3600.0 AS max_overlap_hours
FROM dapt_overlap;