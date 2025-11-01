WITH hf_admissions AS (
  -- Identify admissions with HF diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS admission_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND (
      dd.long_title LIKE '%heart failure%'
      OR dd.icd_code IN ('4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833', '42840', '42841', '42842', '42843', '4289', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'I50.810', 'I50.811', 'I50.813', 'I50.814', 'I50.82', 'I50.83', 'I50.84', 'I50.89', 'I50.9')
    )
),

comorbidity_counts AS (
  -- Count comorbidities per admission, excluding HF
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    NOT (
      dd.long_title LIKE '%heart failure%'
      OR dd.icd_code IN ('4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833', '42840', '42841', '42842', '42843', '4289', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'I50.810', 'I50.811', 'I50.813', 'I50.814', 'I50.82', 'I50.83', 'I50.84', 'I50.89', 'I50.9')
    )
  GROUP BY
    d.hadm_id
),

admission_summary AS (
  SELECT
    hf.hadm_id,
    hf.admission_type,
    hf.hosp_los,
    hf.hospital_expire_flag,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count,
    CASE
      WHEN hf.hosp_los <= 3 THEN '≤3'
      WHEN hf.hosp_los BETWEEN 4 AND 6 THEN '4–6'
      WHEN hf.hosp_los BETWEEN 7 AND 10 THEN '7–10'
      ELSE '>10'
    END AS los_category
  FROM
    hf_admissions hf
  LEFT JOIN
    comorbidity_counts c
    ON hf.hadm_id = c.hadm_id
)

SELECT
  admission_type,
  los_category,
  COUNT(*) AS admission_count,
  AVG(comorbidity_count) AS avg_comorbidity_count,
  AVG(hosp_los) AS mean_los,
  APPROX_QUANTILES(hosp_los, 2)[OFFSET(1)] AS median_los,
  SUM(hospital_expire_flag) AS death_count,
  AVG(hospital_expire_flag) AS in_hosp_mortality_rate
FROM
  admission_summary
GROUP BY
  admission_type,
  los_category
ORDER BY
  admission_type,
  los_category;