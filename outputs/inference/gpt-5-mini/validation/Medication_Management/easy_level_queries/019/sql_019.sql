WITH heparin_rx AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    LOWER(COALESCE(p.drug, '')) AS drug_lower
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  USING (subject_id)
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 58 AND 68
    AND p.hadm_id IS NOT NULL
    -- match heparin/enoxaparin (include common synonym lovenox)
    AND (
      LOWER(COALESCE(p.drug, '')) LIKE '%heparin%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%enoxaparin%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%lovenox%'
    )
    -- require both timestamps present
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
),
durations AS (
  SELECT
    -- duration in fractional days
    TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 86400.0 AS duration_days
  FROM
    heparin_rx
  WHERE
    -- exclude negative durations (if stop before start)
    TIMESTAMP_DIFF(stoptime, starttime, SECOND) >= 0
)
SELECT
  CASE
    WHEN n = 0 THEN NULL
    WHEN MOD(n, 2) = 1 THEN arr[OFFSET(DIV(n, 2))]
    ELSE (arr[OFFSET(DIV(n, 2) - 1)] + arr[OFFSET(DIV(n, 2))]) / 2.0
  END AS median_duration_days,
  n AS prescription_count
FROM (
  SELECT
    arr,
    ARRAY_LENGTH(arr) AS n
  FROM (
    SELECT ARRAY_AGG(duration_days ORDER BY duration_days) AS arr
    FROM durations
  )
)
;