WITH patient_criteria AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),

hospital_los AS (
  SELECT
    hadm_id,
    DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) AS hospital_los_days
  FROM patient_criteria
  WHERE DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) BETWEEN 1 AND 7
),

acs_diagnoses AS (
  SELECT
    di.hadm_id,
    di.seq_num,
    di.icd_code,
    di.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (di.icd_version = 9 AND (di.icd_code LIKE '410.%' OR di.icd_code LIKE '411.1%')) OR
        (di.icd_version = 10 AND di.icd_code IN ('I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9'))
),

acs_type AS (
  SELECT
    hadm_id,
    CASE 
      WHEN MIN(seq_num) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS acs_category
  FROM acs_diagnoses
  GROUP BY hadm_id
),

ultrasound_count AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE LOWER(d.long_description) LIKE '%ultrasound%'
    OR LOWER(d.long_description) LIKE '%echo%'
  GROUP BY h.hadm_id
),

icu_stay_count AS (
  SELECT
    hadm_id,
    COUNT(*) AS icu_stay_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

final_cohort AS (
  SELECT
    pc.hadm_id,
    ac.acs_category,
    COALESCE(usc.icu_stay_count, 0) AS icu_stay_count,
    COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
  FROM patient_criteria pc
  INNER JOIN hospital_los hl ON pc.hadm_id = hl.hadm_id
  INNER JOIN acs_type ac ON pc.hadm_id = ac.hadm_id
  LEFT JOIN ultrasound_count uc ON pc.hadm_id = uc.hadm_id
  LEFT JOIN icu_stay_count usc ON pc.hadm_id = usc.hadm_id
)

SELECT
  CASE 
    WHEN icu_stay_count BETWEEN 1 AND 4 THEN '1-4 stays'
    WHEN icu_stay_count BETWEEN 5 AND 7 THEN '5-7 stays'
  END AS icu_stay_group,
  acs_category,
  APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(75)] AS p75,
  COUNT(*) AS num_admissions
FROM final_cohort
WHERE icu_stay_count BETWEEN 1 AND 7
GROUP BY icu_stay_group, acs_category
ORDER BY icu_stay_group, acs_category;