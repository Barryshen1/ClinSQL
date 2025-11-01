WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission: birth year = anchor_year - anchor_age
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = a.hadm_id
    )
),
pneumonia_admissions AS (
  SELECT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = 10
    AND (dd.long_title LIKE '%pneumonia%' OR d.icd_code IN ('J12', 'J13', 'J15', 'J16', 'J17', 'J18'))
),
aki_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN dd.long_title LIKE '%acute kidney%' OR d.icd_code LIKE 'N17.%' THEN 1 ELSE 0 END) AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = 10
  GROUP BY d.hadm_id
),
ards_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN dd.long_title LIKE '%ARDS%' OR d.icd_code = 'J98.4' OR dd.long_title LIKE '%adult respiratory distress syndrome%' THEN 1 ELSE 0 END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE dd.icd_version = 10
  GROUP BY d.hadm_id
),
drg_severity AS (
  SELECT
    drg.hadm_id,
    MAX(drg.drg_severity) AS composite_risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
  GROUP BY drg.hadm_id
),
cohort AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    e.age_at_admission,
    e.hospital_expire_flag,
    drg.composite_risk_score,
    aki.has_aki,
    ard.has_ards,
    -- Survival days only for in-hospital deaths
    IF(e.hospital_expire_flag = 1, DATEDIFF(e.dischtime, e.admittime), NULL) AS survival_days
  FROM eligible_admissions e
  INNER JOIN pneumonia_admissions p
    ON e.hadm_id = p.hadm_id
  LEFT JOIN drg_severity drg
    ON e.hadm_id = drg.hadm_id
  LEFT JOIN aki_flags aki
    ON e.hadm_id = aki.hadm_id
  LEFT JOIN ards_flags ard
    ON e.hadm_id = ard.hadm_id
)
SELECT
  COUNT(DISTINCT hadm_id) AS cohort_size,
  IFNULL(APPROX_QUANTILES(composite_risk_score, 100, 0)[OFFSET(0)], 0) AS min_risk,
  IFNULL(APPROX_QUANTILES(composite_risk_score, 100, 25)[OFFSET(0)], 0) AS p25_risk,
  IFNULL(APPROX_QUANTILES(composite_risk_score, 100, 50)[OFFSET(0)], 0) AS median_risk,
  IFNULL(APPROX_QUANTILES(composite_risk_score, 100, 75)[OFFSET(0)], 0) AS p75_risk,
  IFNULL(APPROX_QUANTILES(composite_risk_score, 100, 100)[OFFSET(0)], 0) AS max_risk,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate,
  AVG(has_aki) * 100 AS aki_rate,
  AVG(has_ards) * 100 AS ards_rate,
  IFNULL(PERCENTILE_CONT(survival_days, 0.5) OVER (), 0) AS median_survival_days
FROM cohort;