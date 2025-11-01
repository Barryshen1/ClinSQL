WITH hf_admissions AS (
  -- Identify admissions with primary HF diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      dd.icd_code LIKE 'I50%' OR -- ICD-10 for Heart Failure
      (dd.icd_version = 9 AND dd.icd_code LIKE '428%') -- ICD-9 for Heart Failure
    )
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
),

comorbidity_counts AS (
  -- Count non-primary diagnoses as a proxy for comorbidities
  SELECT
    hadm_id,
    COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num > 1
  GROUP BY hadm_id
),

admissions_with_comorbidities AS (
  SELECT
    hf.*,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count,
    CASE
      WHEN los_days <= 5 THEN '≤5 days'
      ELSE '>5 days'
    END AS los_category
  FROM hf_admissions hf
  LEFT JOIN comorbidity_counts c
    ON hf.hadm_id = c.hadm_id
),

comorbidity_tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY comorbidity_count) AS comorbidity_tertile_label,
    CASE
      WHEN comorbidity_count = 0 THEN 'Low'
      WHEN NTILE(3) OVER (ORDER BY comorbidity_count) = 1 THEN 'Low'
      WHEN NTILE(3) OVER (ORDER BY comorbidity_count) = 2 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_tertile
  FROM admissions_with_comorbidities
),

ckd_diabetes_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN dd.long_title LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN dd.long_title LIKE '%chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE d.seq_num > 1
  GROUP BY d.hadm_id
),

final_data AS (
  SELECT
    ct.*,
    COALESCE(cd.has_diabetes, 0) AS has_diabetes,
    COALESCE(cd.has_ckd, 0) AS has_ckd
  FROM comorbidity_tertiles ct
  LEFT JOIN ckd_diabetes_flags cd
    ON ct.hadm_id = cd.hadm_id
)

SELECT
  los_category,
  comorbidity_tertile,
  COUNT(*) AS n,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM final_data
GROUP BY los_category, comorbidity_tertile
ORDER BY los_category, comorbidity_tertile;