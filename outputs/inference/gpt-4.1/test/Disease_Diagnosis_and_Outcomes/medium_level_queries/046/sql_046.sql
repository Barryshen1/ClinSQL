WITH hf_icd_codes AS (
  -- Get all ICD codes for heart failure (ICD-9: 428.x, ICD-10: I50.x)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
     OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
),
hf_admissions AS (
  -- Admissions for males aged 72-82 with HF diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN hf_icd_codes hf
    ON d.icd_code = hf.icd_code AND d.icd_version = hf.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
),
comorbidity_counts AS (
  -- Count distinct diagnoses per admission
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
icu_flags AS (
  -- Flag admissions with ICU stay
  SELECT DISTINCT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
hf_admissions_full AS (
  -- Merge all info
  SELECT
    hfa.subject_id,
    hfa.hadm_id,
    hfa.admittime,
    hfa.dischtime,
    hfa.hospital_expire_flag,
    hfa.anchor_age,
    hfa.gender,
    IFNULL(cf.comorbidity_count, 0) AS comorbidity_count,
    IFNULL(icu.icu_flag, 0) AS icu_flag,
    -- LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(hfa.dischtime, hfa.admittime, SECOND), 86400) AS los_days
  FROM hf_admissions hfa
  LEFT JOIN comorbidity_counts cf
    ON hfa.hadm_id = cf.hadm_id
  LEFT JOIN icu_flags icu
    ON hfa.hadm_id = icu.hadm_id
),
binned_admissions AS (
  -- Bin LOS
  SELECT
    *,
    CASE
      WHEN los_days <= 3 THEN '≤3'
      WHEN los_days > 3 AND los_days <= 6 THEN '4–6'
      WHEN los_days > 6 AND los_days <= 10 THEN '7–10'
      WHEN los_days > 10 THEN '>10'
      ELSE 'Unknown'
    END AS los_bin
  FROM hf_admissions_full
  WHERE los_days IS NOT NULL
)
SELECT
  CASE WHEN icu_flag = 1 THEN 'ICU' ELSE 'Non-ICU' END AS group_type,
  los_bin,
  COUNT(*) AS admission_count,
  SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS in_hospital_mortality_rate,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM binned_admissions
WHERE los_bin != 'Unknown'
GROUP BY group_type, los_bin
ORDER BY group_type, 
  CASE los_bin
    WHEN '≤3' THEN 1
    WHEN '4–6' THEN 2
    WHEN '7–10' THEN 3
    WHEN '>10' THEN 4
    ELSE 5
  END;