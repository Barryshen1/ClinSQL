WITH prescription_durations AS (
  SELECT
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 90 AND 100
    AND p.stoptime >= p.starttime
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
    AND (
      LOWER(p.drug) LIKE '%thiazide%'
      OR LOWER(p.drug) LIKE '%hctz%'
      OR p.drug IN ('chlorthalidone', 'indapamide', 'metolazone', 'bendroflumethiazide', 'cyclopenthiazide')
    )
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER () AS q25,
  PERCENTILE_CONT(duration_days, 0.75) OVER () AS q75,
  PERCENTILE_CONT(duration_days, 0.75) OVER () - PERCENTILE_CONT(duration_days, 0.25) OVER () AS iqr
FROM prescription_durations
LIMIT 1;