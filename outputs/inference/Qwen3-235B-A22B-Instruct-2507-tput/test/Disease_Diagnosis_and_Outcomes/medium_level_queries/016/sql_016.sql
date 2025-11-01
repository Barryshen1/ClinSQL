WITH patients_ami AS (
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%myocardial infarction, acute%'
     OR LOWER(d.long_title) LIKE '%acute myocardial infarction%'
     OR d.icd_code LIKE 'I21%'
     OR d.icd_code LIKE 'I22%'
),
exclusions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%shock%'
     OR LOWER(d.long_title) LIKE '%respiratory failure%'
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_day1,
    CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN patients_ami pa ON a.hadm_id = pa.hadm_id
  LEFT JOIN exclusions e ON a.hadm_id = e.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
    AND i.intime < DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
    AND i.outtime >= a.admittime
  WHERE p.gender = 'M'
    AND e.hadm_id IS NULL  -- No exclusion diagnosis
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) = 45  -- Age 45 at admission
)
SELECT
  los_group,
  icu_day1,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_pct,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM cohort
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;