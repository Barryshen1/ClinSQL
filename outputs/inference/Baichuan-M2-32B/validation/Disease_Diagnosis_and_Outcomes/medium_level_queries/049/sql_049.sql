WITH base_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age_at_admission,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND TIMESTAMP_DIFF(a.admittime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 51 AND 61
    AND a.dischtime IS NOT NULL
),
primary_diagnosis AS (
  SELECT
    d.hadm_id,
    di.long_title,
    CASE 
      WHEN di.long_title LIKE '%transmural%' OR di.long_title LIKE '%STEMI%' THEN 'STEMI'
      WHEN di.long_title LIKE '%without ST segment elevation%' OR di.long_title LIKE '%NSTEMI%' THEN 'NSTEMI'
      ELSE 'Other'
    END AS mi_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    d.seq_num = 1
    AND d.icd_version = 10
),
comorbidities AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN d.icd_code IN ('E10','E11','E12','E13','E14') THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%' OR d.icd_code LIKE 'N25%' THEN 1 ELSE 0 END) AS has_ckd,
    SUM(CASE WHEN d.icd_code IN ('E10','E11','E12','E13','E14') THEN 1 ELSE 0 END) +
    SUM(CASE WHEN d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%' OR d.icd_code LIKE 'N25%' THEN 1 ELSE 0 END) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
  GROUP BY d.hadm_id
),
mi_admissions AS (
  SELECT
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    b.age_at_admission,
    b.los_days,
    p.mi_type,
    COALESCE(c.has_diabetes, 0) AS has_diabetes,
    COALESCE(c.has_ckd, 0) AS has_ckd,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count
  FROM base_admissions b
  LEFT JOIN primary_diagnosis p 
    ON b.hadm_id = p.hadm_id
  LEFT JOIN comorbidities c 
    ON b.hadm_id = c.hadm_id
  WHERE 
    p.mi_type IN ('STEMI', 'NSTEMI')
),
with_prevalence AS (
  SELECT
    *,
    AVG(has_diabetes) OVER (PARTITION BY mi_type) AS diabetes_prevalence,
    AVG(has_ckd) OVER (PARTITION BY mi_type) AS ckd_prevalence
  FROM mi_admissions
),
grouped_data AS (
  SELECT
    mi_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN los_days >= 10 THEN '10+'
      ELSE 'Unknown'
    END AS los_group,
    CASE 
      WHEN comorbidity_count <= 1 THEN '0-1'
      WHEN comorbidity_count = 2 THEN '2'
      WHEN comorbidity_count >= 3 THEN '>=3'
      ELSE 'Unknown'
    END AS comorbidity_group,
    COUNT(*) AS N,
    SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_rate,
    MAX(diabetes_prevalence) AS diabetes_prevalence,
    MAX(ckd_prevalence) AS ckd_prevalence
  FROM with_prevalence
  GROUP BY mi_type, los_group, comorbidity_group
)
SELECT * FROM grouped_data
ORDER BY mi_type, los_group, comorbidity_group;