WITH stroke_patients AS (
  SELECT 
    d.subject_id, 
    d.hadm_id,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '436%')) 
              OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%') THEN 1 ELSE 0 END) AS has_ischemic,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')) THEN 1 ELSE 0 END) AS has_hemorrhagic
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id, d.hadm_id
),
stroke_patients_with_type AS (
  SELECT 
    subject_id, 
    hadm_id,
    CASE 
      WHEN has_ischemic = 1 THEN 'ischemic'
      WHEN has_hemorrhagic = 1 THEN 'hemorrhagic'
      ELSE NULL 
    END AS stroke_type
  FROM stroke_patients
  WHERE has_ischemic = 1 OR has_hemorrhagic = 1
),
patients_with_stroke AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    s.stroke_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN stroke_patients_with_type s ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
ckd_diabetes AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code LIKE '586%')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%')) THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%')) THEN 1 ELSE 0 END) AS has_diabetes
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id, d.hadm_id
),
comorbidity_count AS (
  SELECT 
    d.subject_id,
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN patients_with_stroke p ON d.subject_id = p.subject_id AND d.hadm_id = p.hadm_id
  WHERE NOT (
    (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '436%'))
    OR
    (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%'))
  )
  GROUP BY d.subject_id, d.hadm_id
),
tertiles AS (
  SELECT 
    subject_id,
    hadm_id,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS tertile
  FROM comorbidity_count
)
SELECT 
  t.tertile,
  p.stroke_type,
  AVG(CAST(p.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate,
  AVG(CASE WHEN p.los_days < 8 THEN 1 ELSE 0 END) * 100 AS los_lt8_pct,
  AVG(CASE WHEN p.los_days >= 8 THEN 1 ELSE 0 END) * 100 AS los_ge8_pct,
  AVG(CAST(ckd.has_ckd AS FLOAT64)) * 100 AS ckd_prevalence,
  AVG(CAST(diab.has_diabetes AS FLOAT64)) * 100 AS diabetes_prevalence
FROM patients_with_stroke p
JOIN ckd_diabetes ckd ON p.subject_id = ckd.subject_id AND p.hadm_id = ckd.hadm_id
JOIN comorbidity_count cc ON p.subject_id = cc.subject_id AND p.hadm_id = cc.hadm_id
JOIN tertiles t ON p.subject_id = t.subject_id AND p.hadm_id = t.hadm_id
GROUP BY t.tertile, p.stroke_type;