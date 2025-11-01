WITH hf_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    -- ICD-10: I50 (heart failure), I11.0 (hypertensive heart disease with heart failure), I13.0, I13.2
    (icd_version = 10 AND (icd_code LIKE 'I50%' OR icd_code IN ('I110', 'I130', 'I132')))
    OR
    -- ICD-9: 428
    (icd_version = 9 AND icd_code = '428')
),
patients_in_age_group AS (
  SELECT p.subject_id, p.gender, p.anchor_age, p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
),
admissions_with_age AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Correct age calculation: anchor_age + (admittime year - anchor_year)
    pa.anchor_age + EXTRACT(YEAR FROM a.admittime) - pa.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_in_age_group pa ON a.subject_id = pa.subject_id
),
cohort_with_hf AS (
  SELECT DISTINCT a.*
  FROM admissions_with_age a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN hf_codes hfc ON di.icd_code = hfc.icd_code AND di.icd_version = hfc.icd_version
  WHERE a.age_at_admission >= 72 AND a.age_at_admission <= 82
),
cohort_with_icu_status AS (
  SELECT 
    c.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM cohort_with_hf c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.hadm_id = i.hadm_id
),
cohort_with_comorbidities AS (
  SELECT 
    c.*,
    COALESCE(agg.comorbidity_count, 0) AS comorbidity_count
  FROM cohort_with_icu_status c
  LEFT JOIN (
    SELECT 
      di.hadm_id,
      COUNT(DISTINCT di.icd_code) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN cohort_with_hf c ON di.hadm_id = c.hadm_id
    LEFT JOIN hf_codes hfc ON di.icd_code = hfc.icd_code AND di.icd_version = hfc.icd_version
    WHERE hfc.icd_code IS NULL  -- Exclude HF codes
    GROUP BY di.hadm_id
  ) agg ON c.hadm_id = agg.hadm_id
),
categorized_los AS (
  SELECT *,
    CASE
      WHEN los_days <= 3 THEN '≤3 days'
      WHEN los_days <= 6 THEN '4–6 days'
      WHEN los_days <= 10 THEN '7–10 days'
      ELSE '>10 days'
    END AS los_group
  FROM cohort_with_comorbidities
)
SELECT
  icu_status,
  -- In-hospital mortality rate
  AVG(hospital_expire_flag) AS mortality_rate,
  -- Median LOS
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  -- Average comorbidity count
  AVG(comorbidity_count) AS avg_comorbidity_count,
  -- Also show LOS distribution (optional, but useful)
  COUNT(*) AS n_admissions
FROM categorized_los
GROUP BY icu_status
ORDER BY icu_status;