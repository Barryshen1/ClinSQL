WITH cohort AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),
arb_rx AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    pr.starttime,
    pr.stoptime,
    SAFE_CAST(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS INT64) AS duration_days
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id
   AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(pr.drug), r'(losartan|valsartan|irbesartan|candesartan|telmisartan|olmesartan|eprosartan|azilsartan)')
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS percentile_75_duration_days
FROM arb_rx
WHERE duration_days >= 0;