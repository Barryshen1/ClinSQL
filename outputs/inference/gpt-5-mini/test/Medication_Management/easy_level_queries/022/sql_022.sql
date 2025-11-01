WITH ccb_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(TIMESTAMP(pr.stoptime), TIMESTAMP(pr.starttime), SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON pr.subject_id = pt.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pr.hadm_id = adm.hadm_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 59 AND 69
    AND pr.hadm_id IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND TIMESTAMP(pr.starttime) >= adm.admittime
    AND TIMESTAMP(pr.stoptime) <= adm.dischtime
    AND TIMESTAMP(pr.stoptime) > TIMESTAMP(pr.starttime)
    AND REGEXP_CONTAINS(
      LOWER(COALESCE(pr.drug, '')),
      r'(amlodipine|nifedipine|felodipine|nicardipine|isradipine|nimodipine|lercanidipine|nisoldipine|clevidipine)'
    )
)

SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days,
  COUNT(*) AS n_prescriptions,
  COUNT(DISTINCT subject_id) AS n_patients
FROM ccb_prescriptions;