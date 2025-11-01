WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 52 AND 62
),

stroke_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN d.icd_code IN ('I63', 'I64') THEN 'Ischemic'
      WHEN d.icd_code IN ('I61', 'I62') THEN 'Hemorrhagic'
    END AS stroke_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN female_patients fp
    ON a.subject_id = fp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE d.icd_code IN ('I63', 'I61', 'I62', 'I64')
    AND d.seq_num = 1
),

comorbidity_count AS (
  SELECT
    sa.hadm_id,
    sa.stroke_type,
    sa.hospital_expire_flag,
    sa.los_days,
    COUNT(d2.icd_code) AS comorbidity_score
  FROM stroke_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON sa.hadm_id = d2.hadm_id
  WHERE d2.seq_num > 1
  GROUP BY sa.hadm_id, sa.stroke_type, sa.hospital_expire_flag, sa.los_days
),

comorbidity_tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY comorbidity_score) AS comorbidity_tertile
  FROM comorbidity_count
),

ckd_diabetes AS (
  SELECT
    ct.hadm_id,
    MAX(CASE WHEN did.icd_code IN ('N18', 'N181', 'N182', 'N183', 'N184', 'N185', 'N186') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN did.icd_code IN ('E10', 'E11', 'E12', 'E13', 'E14') THEN 1 ELSE 0 END) AS has_diabetes
  FROM comorbidity_tertiles ct
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ct.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE d.seq_num > 1
  GROUP BY ct.hadm_id
),

final_data AS (
  SELECT
    ct.stroke_type,
    ct.comorbidity_tertile,
    ct.hospital_expire_flag,
    ct.los_days,
    COALESCE(cd.has_ckd, 0) AS has_ckd,
    COALESCE(cd.has_diabetes, 0) AS has_diabetes
  FROM comorbidity_tertiles ct
  LEFT JOIN ckd_diabetes cd
    ON ct.hadm_id = cd.hadm_id
)

SELECT
  stroke_type,
  comorbidity_tertile,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS in_hosp_mortality_pct,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  SUM(CASE WHEN los_days < 8 THEN 1 ELSE 0 END) AS los_lt_8,
  SUM(CASE WHEN los_days >= 8 THEN 1 ELSE 0 END) AS los_ge_8,
  AVG(has_ckd) * 100 AS ckd_prevalence_pct,
  AVG(has_diabetes) * 100 AS diabetes_prevalence_pct
FROM final_data
GROUP BY stroke_type, comorbidity_tertile
ORDER BY stroke_type, comorbidity_tertile;