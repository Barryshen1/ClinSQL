WITH aki_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%acute kidney injury%'
     OR long_title LIKE '%acute renal failure%'
     OR icd_code LIKE 'N17%'
),

ards_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%acute respiratory distress syndrome%'
     OR icd_code LIKE 'J80%'
),

aki_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    p.dod,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN aki_codes ac 
    ON d.icd_code = ac.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

comorbidities AS (
  SELECT 
    d.hadm_id,
    COUNT(*) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN aki_patients ap 
    ON d.hadm_id = ap.hadm_id
  LEFT JOIN aki_codes ac 
    ON d.icd_code = ac.icd_code
  WHERE ac.icd_code IS NULL
  GROUP BY d.hadm_id
),

ards_presence AS (
  SELECT 
    d.hadm_id,
    MAX(CASE WHEN ac.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN aki_patients ap 
    ON d.hadm_id = ap.hadm_id
  LEFT JOIN ards_codes ac 
    ON d.icd_code = ac.icd_code
  GROUP BY d.hadm_id
),

patient_data AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    ap.admittime,
    ap.dischtime,
    ap.hospital_expire_flag,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count,
    COALESCE(a.has_ards, 0) AS has_ards,
    (5 * COALESCE(c.comorbidity_count, 0) + 50 * COALESCE(a.has_ards, 0)) AS composite_risk,
    CASE
      WHEN ap.hospital_expire_flag = 1 THEN 0
      WHEN ap.dod IS NOT NULL AND ap.dod <= DATE_ADD(ap.dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS thirty_day_mortality,
    DATE_DIFF(ap.dischtime, ap.admittime, DAY) AS los
  FROM aki_patients ap
  LEFT JOIN comorbidities c 
    ON ap.hadm_id = c.hadm_id
  LEFT JOIN ards_presence a 
    ON ap.hadm_id = a.hadm_id
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY composite_risk) AS risk_quintile,
    CASE WHEN thirty_day_mortality = 0 THEN los ELSE NULL END AS survivor_los
  FROM patient_data
)

SELECT
  risk_quintile,
  COUNT(*) AS N,
  AVG(thirty_day_mortality) * 100 AS thirty_day_mortality_percent,
  AVG(has_ards) * 100 AS ards_co_occurrence_percent,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY survivor_los) AS median_survivor_los
FROM quintiles
GROUP BY risk_quintile
ORDER BY risk_quintile;