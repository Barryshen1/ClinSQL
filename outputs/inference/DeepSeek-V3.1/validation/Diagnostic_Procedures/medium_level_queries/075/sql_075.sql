WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate length of stay in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Categorize LOS
    CASE 
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other' 
    END AS los_group,
    d.seq_num,
    -- Categorize diagnosis priority
    CASE 
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary' 
    END AS diagnosis_priority
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    -- ACS codes: ICD-10 I21.x and I20.0
    AND (
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code = 'I20.0'))
      OR 
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '411.1'))
    )
),

procedure_counts AS (
  SELECT 
    c.hadm_id,
    c.los_group,
    c.diagnosis_priority,
    COUNT(DISTINCT p.icd_code) AS num_procedures
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON c.hadm_id = p.hadm_id
  WHERE c.los_group IN ('1-3 days', '4-7 days')
  GROUP BY c.hadm_id, c.los_group, c.diagnosis_priority
)

SELECT 
  los_group,
  diagnosis_priority,
  COUNT(*) AS num_admissions,
  APPROX_QUANTILES(num_procedures, 100) [SAFE_ORDINAL(25)] AS p25,
  APPROX_QUANTILES(num_procedures, 100) [SAFE_ORDINAL(50)] AS p50,
  APPROX_QUANTILES(num_procedures, 100) [SAFE_ORDINAL(75)] AS p75
FROM procedure_counts
GROUP BY los_group, diagnosis_priority
ORDER BY los_group, diagnosis_priority;