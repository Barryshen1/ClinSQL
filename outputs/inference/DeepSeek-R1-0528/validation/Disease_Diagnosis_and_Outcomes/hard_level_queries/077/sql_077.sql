WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime, 
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.hadm_id IN (
      SELECT DISTINCT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND (REGEXP_CONTAINS(icd_code, r'^48[0-6]') OR icd_code LIKE '487%' OR icd_code LIKE '488%'))
        OR 
        (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J1[2-8]|J69|P23|U04|B01\.2|B05\.2|B37\.1|B59|B25\.0|B44\.[0-2]'))
    )
    AND a.hadm_id IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`)
),
cohort_icu AS (
  SELECT 
    c.*,
    i.stay_id,
    i.intime,
    i.outtime
  FROM cohort c
  JOIN (
    SELECT 
      hadm_id, 
      stay_id, 
      intime, 
      outtime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i 
    ON c.hadm_id = i.hadm_id AND i.rn = 1
  WHERE c.age_at_admission BETWEEN 88 AND 98
),
gcs AS (
  SELECT 
    ci.stay_id,
    MIN(ce.valuenum) AS min_gcs
  FROM cohort_icu ci
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ci.stay_id = ce.stay_id
  WHERE ce.itemid = 226  -- Glasgow Coma Score (GCS)
    AND ce.charttime BETWEEN ci.intime AND DATETIME_ADD(ci.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ci.stay_id
),
sofa_cns AS (
  SELECT 
    stay_id,
    CASE
      WHEN min_gcs < 6 THEN 4
      WHEN min_gcs BETWEEN 6 AND 9 THEN 3
      WHEN min_gcs BETWEEN 10 AND 12 THEN 2
      WHEN min_gcs BETWEEN 13 AND 14 THEN 1
      ELSE 0
    END AS cns_score
  FROM gcs
),
sofa_scores AS (
  SELECT 
    ci.hadm_id,
    COALESCE(sc.cns_score, 0) AS sofa_score  -- Default 0 if no GCS
  FROM cohort_icu ci
  LEFT JOIN sofa_cns sc 
    ON ci.stay_id = sc.stay_id
),
aki_flags AS (
  SELECT 
    hadm_id,
    MAX(1) AS aki_flag  -- Flag if AKI diagnosis exists
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^584'))
    OR 
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N17|N19'))
  GROUP BY hadm_id
),
ards_flags AS (
  SELECT 
    hadm_id,
    MAX(1) AS ards_flag  -- Flag if ARDS diagnosis exists
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
  WHERE 
    (icd_version = 9 AND icd_code = '518.82')
    OR 
    (icd_version = 10 AND icd_code = 'J80')
  GROUP BY hadm_id
),
cohort_outcomes AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    COALESCE(ak.aki_flag, 0) AS aki_flag,
    COALESCE(ar.ards_flag, 0) AS ards_flag,
    ss.sofa_score
  FROM cohort_icu c
  LEFT JOIN sofa_scores ss 
    ON c.hadm_id = ss.hadm_id
  LEFT JOIN aki_flags ak 
    ON c.hadm_id = ak.hadm_id
  LEFT JOIN ards_flags ar 
    ON c.hadm_id = ar.hadm_id
),
survival_days AS (
  SELECT 
    DATE_DIFF(deathtime, admittime, DAY) AS survival_days
  FROM cohort_icu
  WHERE hospital_expire_flag = 1  -- Only decedents
)
SELECT 
  COUNT(DISTINCT hadm_id) AS cohort_size,
  MIN(sofa_score) AS min_risk_score,
  APPROX_QUANTILES(sofa_score, 4)[OFFSET(1)] AS q1_risk_score,
  APPROX_QUANTILES(sofa_score, 4)[OFFSET(2)] AS median_risk_score,
  APPROX_QUANTILES(sofa_score, 4)[OFFSET(3)] AS q3_risk_score,
  MAX(sofa_score) AS max_risk_score,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_rate,
  ROUND(AVG(aki_flag) * 100, 2) AS aki_rate,
  ROUND(AVG(ards_flag) * 100, 2) AS ards_rate,
  (SELECT APPROX_QUANTILES(t.survival_days, 2)[OFFSET(1)] FROM survival_days t) AS median_survival_days
FROM cohort_outcomes;