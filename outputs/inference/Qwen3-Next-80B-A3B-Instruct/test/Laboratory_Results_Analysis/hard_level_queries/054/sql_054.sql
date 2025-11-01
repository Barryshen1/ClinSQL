WITH amipatients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code IN ('I21', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I22', 'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9'))
    )
),
controls AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.hadm_id NOT IN (SELECT hadm_id FROM amipatients)
),
lab_abnormalities_fixed AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON le.hadm_id = a.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.charttime <= a.admittime + INTERVAL '72' HOUR
    AND le.flag IS NOT NULL  -- Use flag as the only validated indicator of abnormality in MIMIC-IV
  GROUP BY le.subject_id, le.hadm_id
),
ami_with_score AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    ap.admittime,
    ap.dischtime,
    ap.hospital_expire_flag,
    COALESCE(lab.abnormal_lab_count, 0) AS lab_instability_score
  FROM amipatients ap
  LEFT JOIN lab_abnormalities_fixed lab ON ap.hadm_id = lab.hadm_id
),
control_with_score AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COALESCE(lab.abnormal_lab_count, 0) AS abnormal_lab_count
  FROM controls c
  LEFT JOIN lab_abnormalities_fixed lab ON c.hadm_id = lab.hadm_id
),
quartiles AS (
  SELECT 
    subject_id,
    hadm_id,
    lab_instability_score,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile,
    dischtime,
    admittime,
    hospital_expire_flag
  FROM ami_with_score
)
SELECT 
  q.quartile,
  AVG(TIMESTAMP_DIFF(q.dischtime, q.admittime, HOUR) / 24.0) AS avg_los_days,
  SUM(q.hospital_expire_flag) * 1.0 / COUNT(*) AS in_hospital_mortality_rate
FROM quartiles q
GROUP BY q.quartile
ORDER BY q.quartile;