WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 78 AND 88
    AND a.dischtime IS NOT NULL
),
ace_prescriptions AS (
  SELECT
    c.hadm_id,
    p.starttime,
    p.stoptime,
    c.admittime,
    c.dischtime,
    GREATEST(0, 
      DATETIME_DIFF(
        LEAST(COALESCE(p.stoptime, c.dischtime), c.dischtime),
        GREATEST(p.starttime, c.admittime),
        SECOND
      )
    ) / (24*60*60) AS duration_days
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE 
    p.drug_type IN ('ICU', 'INPATIENT')
    AND REGEXP_CONTAINS(LOWER(p.drug), r'benazepril|captopril|enalapril|fosinopril|lisinopril|moexipril|perindopril|quinapril|ramipril|trandolapril')
    AND p.starttime IS NOT NULL
)
SELECT STDDEV_POP(duration_days) AS sd_duration_days
FROM ace_prescriptions
WHERE duration_days > 0;