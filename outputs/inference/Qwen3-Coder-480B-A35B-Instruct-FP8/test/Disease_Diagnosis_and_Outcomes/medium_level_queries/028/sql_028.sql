WITH hf_admissions AS (
  -- Identify admissions with HF diagnosis
  SELECT DISTINCT
    di.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a ON di.hadm_id = a.hadm_id
  WHERE
    LOWER(d.long_title) LIKE '%heart failure%'
),

comorbidity_count AS (
  -- Count distinct diagnoses per admission as a proxy for comorbidity burden
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd
  GROUP BY
    hadm_id
),

eligible_patients AS (
  -- Filter patients by gender and age
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ha.hadm_id,
    ha.los_days,
    ha.hospital_expire_flag,
    cc.comorbidity_count
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    hf_admissions ha ON p.subject_id = ha.subject_id
  JOIN
    comorbidity_count cc ON ha.hadm_id = cc.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

stratified_data AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    -- Compute LOS quartiles
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile,
    -- Stratify comorbidity burden
    CASE
      WHEN comorbidity_count <= 5 THEN 'Low'
      WHEN comorbidity_count <= 10 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_burden
  FROM
    eligible_patients
)

SELECT
  los_quartile,
  comorbidity_burden,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100, 2) AS mortality_percent
FROM
  stratified_data
GROUP BY
  los_quartile,
  comorbidity_burden
ORDER BY
  los_quartile,
  comorbidity_burden;