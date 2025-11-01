WITH stroke_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'M'
    AND di.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-10: Ischemic stroke (I63.x)
      (di.icd_version = 10 AND di.icd_code LIKE 'I63%')
      OR 
      -- ICD-9: Cerebral infarction with occlusion (433.x1, 434.x1) or acute stroke (436)
      (di.icd_version = 9 AND di.icd_code IN (
        '43301', '43311', '43321', '43331', '43381', '43391',
        '43401', '43411', '43491', '436'
      ))
    )
    AND a.dischtime > a.admittime  -- Ensure valid LOS
)
SELECT 
  MAX(los_days) AS max_los_days
FROM 
  stroke_admissions
WHERE 
  age_at_admission BETWEEN 84 AND 94;