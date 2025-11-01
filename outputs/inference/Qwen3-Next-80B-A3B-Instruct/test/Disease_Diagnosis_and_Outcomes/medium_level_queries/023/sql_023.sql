WITH patients_filtered AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 52 AND 62
),

stroke_diagnoses AS (
  SELECT 
    di.subject_id,
    di.hadm_id,
    CASE 
      WHEN di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) IN ('430', '431') THEN 'hemorrhagic'
      WHEN di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) IN ('I60', 'I61') THEN 'hemorrhagic'
      WHEN di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) IN ('433', '434', '436') THEN 'ischemic'
      WHEN di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) IN ('I63') THEN 'ischemic'
      ELSE NULL
    END AS stroke_type
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN patients_filtered p ON di.subject_id = p.subject_id
  WHERE di.seq_num = 1
    AND (
      (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) IN ('430', '431', '433', '434', '436'))
      OR
      (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) IN ('I60', 'I61', 'I63'))
    )
),

comorbidity_counts AS (
  SELECT 
    di.subject_id,
    SUM(CASE 
      WHEN di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) IN ('585', '586') THEN 1
      WHEN di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) IN ('N18') THEN 1
      ELSE 0
    END) AS ckd_count,
    SUM(CASE 
      WHEN di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) = '250' THEN 1
      WHEN di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) IN ('E10', 'E11', 'E13') THEN 1
      ELSE 0
    END) AS diabetes_count
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN patients_filtered p ON di.subject_id = p.subject_id
  GROUP BY di.subject_id
),

comorbidity_tertiles AS (
  SELECT 
    subject_id,
    ckd_count,
    diabetes_count,
    ckd_count + diabetes_count AS comorbidity_score,
    NTILE(3) OVER (ORDER BY ckd_count + diabetes_count) AS comorbidity_tertile
  FROM comorbidity_counts
),

admissions_with_los AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8'
      ELSE '>=8'
    END AS los_category
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
),

final_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.los_days,
    a.los_category,
    ct.comorbidity_tertile,
    ct.ckd_count,
    ct.diabetes_count,
    sd.stroke_type
  FROM admissions_with_los a
  INNER JOIN comorbidity_tertiles ct ON a.subject_id = ct.subject_id
  LEFT JOIN stroke_diagnoses sd ON a.subject_id = sd.subject_id AND a.hadm_id = sd.hadm_id
)

SELECT
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_pct,
  AVG(CASE WHEN los_category = '<8' THEN 1.0 ELSE 0.0 END) * 100 AS los_less_than_8_pct,
  AVG(CASE WHEN los_category = '>=8' THEN 1.0 ELSE 0.0 END) * 100 AS los_greater_equal_8_pct,
  comorbidity_tertile,
  AVG(CASE WHEN ckd_count > 0 THEN 1.0 ELSE 0.0 END) * 100 AS ckD_prevalence_pct,
  AVG(CASE WHEN diabetes_count > 0 THEN 1.0 ELSE 0.0 END) * 100 AS diabetes_prevalence_pct
FROM final_data
GROUP BY comorbidity_tertile
ORDER BY comorbidity_tertile;