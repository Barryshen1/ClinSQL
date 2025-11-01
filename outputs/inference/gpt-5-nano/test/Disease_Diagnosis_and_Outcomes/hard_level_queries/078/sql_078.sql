WITH HF_ADMISSIONS AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id AND di.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
),
POP AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN HF_ADMISSIONS AS h ON a.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 59 AND 69
),
AKI AS (
  SELECT hadm_id, 1 AS aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM POP)
    AND (di.icd_code LIKE '584%' OR di.icd_code LIKE 'N17%')
  GROUP BY hadm_id
),
ARDS AS (
  SELECT hadm_id, 1 AS ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM POP)
    AND (di.icd_code LIKE '518.5%' OR di.icd_code LIKE 'J80%')
  GROUP BY hadm_id
),
BASE AS (
  SELECT
    s.hadm_id,
    s.subject_id,
    s.admittime,
    s.dischtime,
    s.deathtime,
    s.hospital_expire_flag,
    s.gender,
    s.anchor_age,
    COALESCE(a.aki, 0) AS aki_flag,
    COALESCE(ar.ards, 0) AS ards_flag,
    CASE WHEN s.anchor_age >= 65 THEN 1 ELSE 0 END AS age65_flag,
    CASE
      WHEN s.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(s.deathtime, s.admittime, SECOND) / 86400.0
      ELSE TIMESTAMP_DIFF(s.dischtime, s.admittime, SECOND) / 86400.0
    END AS los_days
  FROM POP AS s
  LEFT JOIN AKI AS a ON s.hadm_id = a.hadm_id
  LEFT JOIN ARDS AS ar ON s.hadm_id = ar.hadm_id
),
PER_ROW AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    gender,
    anchor_age,
    aki_flag,
    ards_flag,
    age65_flag,
    los_days,
    (aki_flag + ards_flag + age65_flag + los_days) AS risk_score
  FROM BASE
),
SURVIVAL AS (
  SELECT
    (TIMESTAMP_DIFF(p.deathtime, p.admittime, SECOND) / 86400.0) AS survival_days
  FROM POP AS p
  WHERE p.hospital_expire_flag = 1
),
QUANT AS (
  SELECT APPROX_QUANTILES(risk_score, 100) AS q
  FROM PER_ROW
),
SUMMARY AS (
  SELECT
    COUNT(*) AS n_patients,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS ih_mortality_rate,
    SAFE_DIVIDE(SUM(aki_flag), COUNT(*)) AS aki_rate,
    SAFE_DIVIDE(SUM(ards_flag), COUNT(*)) AS ards_rate,
    MIN(risk_score) AS min_risk,
    MAX(risk_score) AS max_risk
  FROM PER_ROW
),
SURVIVAL_MEDIAN AS (
  SELECT
    (SELECT q[OFFSET(49)] FROM QUANT) AS median_survival_days
  FROM SURVIVAL
  LIMIT 1
),
RISK_DIST AS (
  SELECT
    q[OFFSET(24)] AS p25_risk,
    q[OFFSET(49)] AS median_risk,
    q[OFFSET(74)] AS p75_risk,
    q[OFFSET(89)] AS p90_risk
  FROM QUANT
)
SELECT
  s.n_patients,
  s.ih_mortality_rate,
  s.aki_rate,
  s.ards_rate,
  sm.median_survival_days,
  r.p25_risk,
  r.median_risk,
  r.p75_risk,
  r.p90_risk,
  s.min_risk,
  s.max_risk
FROM SUMMARY AS s
CROSS JOIN SURVIVAL_MEDIAN AS sm
CROSS JOIN RISK_DIST AS r
ORDER BY s.n_patients;