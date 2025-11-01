WITH
-- Define age at admission
patient_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
),

-- Identify stroke types
stroke_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN d.icd_code LIKE 'I63%' THEN 'Ischemic'
      WHEN d.icd_code LIKE 'I61%' THEN 'Hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I63%'
),

-- Identify CKD and diabetes comorbidities
comorbidities AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  GROUP BY
    d.subject_id, d.hadm_id
),

-- Count comorbidities (excluding stroke) for tertiles
comorbidity_counts AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.icd_code NOT LIKE 'I61%' AND d.icd_code NOT LIKE 'I63%'
  GROUP BY
    d.subject_id, d.hadm_id
),

-- Calculate tertiles
comorbidity_tertile AS (
  SELECT
    subject_id,
    hadm_id,
    comorbidity_count,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS tertile
  FROM
    comorbidity_counts
),

-- Combine all data
patient_data AS (
  SELECT
    p.subject_id,
    pa.hadm_id,
    p.gender,
    pa.age,
    sd.stroke_type,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    c.has_diabetes,
    c.has_ckd,
    ct.tertile
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    patient_age pa ON p.subject_id = pa.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON pa.subject_id = a.subject_id AND pa.hadm_id = a.hadm_id
  JOIN
    stroke_diagnoses sd ON a.subject_id = sd.subject_id AND a.hadm_id = sd.hadm_id
  JOIN
    comorbidities c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  JOIN
    comorbidity_tertile ct ON a.subject_id = ct.subject_id AND a.hadm_id = ct.hadm_id
  WHERE
    p.gender = 'F'
    AND pa.age BETWEEN 52 AND 62
)

-- Final aggregation
SELECT
  stroke_type,
  tertile,
  COUNT(*) AS patient_count,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(AVG(CASE WHEN los_days < 8 THEN 1 ELSE 0 END) * 100, 2) AS los_less_than_8_pct,
  ROUND(AVG(CASE WHEN los_days >= 8 THEN 1 ELSE 0 END) * 100, 2) AS los_8_or_more_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct
FROM
  patient_data
GROUP BY
  stroke_type, tertile
ORDER BY
  stroke_type, tertile;