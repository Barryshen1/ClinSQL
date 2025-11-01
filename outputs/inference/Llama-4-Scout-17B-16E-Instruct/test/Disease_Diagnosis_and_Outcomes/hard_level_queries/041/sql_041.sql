WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.hospital_expire_flag = 0
),

-- Identify ICH patients
ich_patients AS (
  SELECT 
    poi.subject_id,
    poi.hadm_id,
    poi.admittime,
    poi.dischtime,
    poi.deathtime
  FROM 
    patients_of_interest poi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON poi.hadm_id = di.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    dd.long_title LIKE '%Intracranial hemorrhage%'
),

-- Identify ICU transfers
icu_transfers AS (
  SELECT 
    it.subject_id,
    it.hadm_id,
    it.intime,
    it.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.transfers` t 
      ON icu.hadm_id = t.hadm_id AND icu.first_careunit = t.careunit
  WHERE 
    icu.stay_id IS NOT NULL
),

-- Identify AKI and ARDS
aki_ards AS (
  SELECT 
    subject_id,
    hadm_id,
    itemid,
    charttime,
    value,
    valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label IN ('AKI', 'ARDS'))
),

-- Calculate 30-day mortality, AKI, ARDS, and survival
cohort_data AS (
  SELECT 
    ip.subject_id,
    ip.hadm_id,
    ip.admittime,
    ip.deathtime,
    CASE 
      WHEN ad.deathtime IS NOT NULL AND DATE_DIFF(ad.deathtime, ip.admittime) <= 30 THEN 1 
      ELSE 0 
    END AS thirty_day_mortality,
    CASE 
      WHEN aki.itemid IS NOT NULL THEN 1 
      ELSE 0 
    END AS aki,
    CASE 
      WHEN ards.itemid IS NOT NULL THEN 1 
      ELSE 0 
    END AS ards
  FROM 
    ich_patients ip
  LEFT JOIN 
    aki_ards aki ON ip.hadm_id = aki.hadm_id
  LEFT JOIN 
    aki_ards ards ON ip.hadm_id = ards.hadm_id
  LEFT JOIN 
    patients_of_interest ad ON ip.subject_id = ad.subject_id
)

-- Final calculations
SELECT 
  COUNT(DISTINCT subject_id) AS cohort_size,
  AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
  AVG(aki) AS aki_rate,
  AVG(ards) AS ards_rate,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY thirty_day_mortality) AS risk_score_25th,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY thirty_day_mortality) AS risk_score_median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY thirty_day_mortality) AS risk_score_75th,
  APPROX_QUANTILES(CASE WHEN deathtime IS NOT NULL THEN DATE_DIFF(deathtime, admittime) END, 1000)[OFFSET(500)] AS median_survival
FROM 
  cohort_data;