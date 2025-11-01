WITH ace_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    SAFE_DIVIDE(TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND), 86400) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age = 55
    -- ensure valid times and inpatient prescription during the admission
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND p.starttime BETWEEN a.admittime AND a.dischtime
    -- match common ACE inhibitors by drug name (case-insensitive)
    AND REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')), r'(lisinopril|enalapril|ramipril|captopril|benazepril|perindopril|quinapril|fosinopril|moexipril|trandolapril|cilazapril)')
)

SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS p25_duration_days,
  COUNT(*) AS total_ace_prescriptions_used_for_estimate
FROM ace_prescriptions;