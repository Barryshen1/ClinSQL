WITH arb_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON p.subject_id = pat.subject_id
  WHERE
    (pat.gender = 'F' OR pat.gender = 'Female')
    AND pat.anchor_age BETWEEN 77 AND 87
    AND (
      LOWER(p.drug) LIKE '%losartan%'  OR
      LOWER(p.drug) LIKE '%valsartan%' OR
      LOWER(p.drug) LIKE '%irbesartan%' OR
      LOWER(p.drug) LIKE '%candesartan%' OR
      LOWER(p.drug) LIKE '%telmisartan%' OR
      LOWER(p.drug) LIKE '%olmesartan%' OR
      LOWER(p.drug) LIKE '%eprosartan%' OR
      LOWER(p.drug) LIKE '%azilsartan%'
    )
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.starttime >= a.admittime
    AND p.starttime < a.dischtime
)
SELECT
  AVG(duration_days) AS avg_duration_days
FROM arb_prescriptions;