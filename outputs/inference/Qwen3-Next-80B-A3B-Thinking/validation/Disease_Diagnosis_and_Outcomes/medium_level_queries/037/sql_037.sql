WITH sepsis_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE 
      WHEN MAX(CASE WHEN d.icd_code = 'R65.21' THEN 1 ELSE 0 END) = 1 THEN 'septic shock'
      WHEN MAX(CASE WHEN d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' THEN 1 ELSE 0 END) = 1 THEN 'no shock'
    END AS sepsis_severity,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON p.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code = 'R65.21')
  GROUP BY p.subject_id, a.hadm_id, a.admission_type, a.admittime, a.dischtime, a.hospital_expire_flag
),
comorbidities AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code NOT LIKE 'A40%' 
    AND d.icd_code NOT LIKE 'A41%' 
    AND d.icd_code != 'R65.21'
  GROUP BY d.subject_id, d.hadm_id
)
SELECT 
  sp.sepsis_severity,
  CASE 
    WHEN sp.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN sp.los_days BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END AS los_category,
  sp.admission_type,
  SUM(sp.hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_rate,
  AVG(COALESCE(c.comorbidity_count, 0)) AS mean_comorbidity_count
FROM sepsis_patients sp
LEFT JOIN comorbidities c 
  ON sp.subject_id = c.subject_id AND sp.hadm_id = c.hadm_id
GROUP BY sp.sepsis_severity, los_category, sp.admission_type;