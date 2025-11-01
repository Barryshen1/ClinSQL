WITH male_38_48 AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),
arb_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN male_38_48 pop
    ON pr.subject_id = pop.subject_id
    AND pr.hadm_id = pop.hadm_id
  WHERE
    LOWER(pr.drug) LIKE '%losartan%'
    OR LOWER(pr.drug) LIKE '%valsartan%'
    OR LOWER(pr.drug) LIKE '%candesartan%'
    OR LOWER(pr.drug) LIKE '%irbesartan%'
    OR LOWER(pr.drug) LIKE '%olmesartan%'
    OR LOWER(pr.drug) LIKE '%telmisartan%'
    OR LOWER(pr.drug) LIKE '%eprosartan%'
    OR LOWER(pr.drug) LIKE '%azilsartan%'
),
presc_durations AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    SAFE_CAST(DATE_DIFF(DATE(stoptime), DATE(starttime), DAY) AS INT64) AS duration_days
  FROM arb_prescriptions
  WHERE starttime IS NOT NULL
    AND stoptime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS arb_prescription_75th_percentile_days
FROM presc_durations
WHERE duration_days > 0;