WITH cohort_admissions AS (
  -- admissions for female patients age 78-88 with a diagnosis mentioning "cardiac arrest"
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON dx.icd_code = dicd.icd_code
   AND dx.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(dicd.long_title) LIKE '%cardiac arrest%'
),

meds_in_7d AS (
  -- prescriptions that start within first 7 days of admission
  SELECT
    ca.subject_id,
    ca.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    p.route
  FROM cohort_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON ca.hadm_id = p.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.starttime >= ca.admittime
    AND p.starttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 7 DAY)
),

-- high-risk drug identification via pattern matching on drug name; expand list as needed
meds_flagged AS (
  SELECT
    m.*,
    CASE
      WHEN LOWER(m.drug) LIKE '%warfarin%' THEN 1
      WHEN LOWER(m.drug) LIKE '%heparin%' THEN 1
      WHEN LOWER(m.drug) LIKE '%enoxaparin%' THEN 1
      WHEN LOWER(m.drug) LIKE '%dabigatran%' THEN 1
      WHEN LOWER(m.drug) LIKE '%rivaroxaban%' THEN 1
      WHEN LOWER(m.drug) LIKE '%apixaban%' THEN 1
      WHEN LOWER(m.drug) LIKE '%insulin%' THEN 1
      WHEN LOWER(m.drug) LIKE '%morphine%' THEN 1
      WHEN LOWER(m.drug) LIKE '%hydromorphone%' THEN 1
      WHEN LOWER(m.drug) LIKE '%oxycodone%' THEN 1
      WHEN LOWER(m.drug) LIKE '%fentanyl%' THEN 1
      WHEN LOWER(m.drug) LIKE '%midazolam%' THEN 1
      WHEN LOWER(m.drug) LIKE '%lorazepam%' THEN 1
      WHEN LOWER(m.drug) LIKE '%diazepam%' THEN 1
      WHEN LOWER(m.drug) LIKE '%aspirin%' THEN 1
      WHEN LOWER(m.drug) LIKE '%clopidogrel%' THEN 1
      ELSE 0
    END AS is_high_risk
  FROM meds_in_7d m
),

per_admission_score AS (
  -- compute unique drug count, high-risk distinct drug count, distinct routes, and score per admission
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    COALESCE(COUNT(DISTINCT LOWER(mf.drug)), 0) AS unique_drug_count,
    COALESCE(COUNT(DISTINCT LOWER(CASE WHEN mf.is_high_risk = 1 THEN mf.drug END)), 0) AS high_risk_drug_count,
    COALESCE(COUNT(DISTINCT NULLIF(TRIM(mf.route), '')), 0) AS route_count
  FROM cohort_admissions ca
  LEFT JOIN meds_flagged mf
    ON ca.hadm_id = mf.hadm_id
  GROUP BY ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, ca.hospital_expire_flag
),

scores AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    unique_drug_count,
    high_risk_drug_count,
    route_count,
    -- score = unique drugs + 2 * high-risk drugs + routes
    (COALESCE(unique_drug_count, 0) + 2 * COALESCE(high_risk_drug_count, 0) + COALESCE(route_count, 0)) AS score
  FROM per_admission_score
),

scores_with_tertile AS (
  -- assign tertiles based on score distribution across the cohort
  SELECT
    s.*,
    NTILE(3) OVER (ORDER BY score) AS tertile
  FROM scores s
),

readmit30_flag AS (
  -- for each index admission, determine if there is any readmission for the same subject within 30 days after discharge
  SELECT
    swt.*,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = swt.subject_id
          AND a2.admittime > swt.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(swt.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0 END AS readmit_30d_flag,
    -- LOS in fractional days
    (TIMESTAMP_DIFF(swt.dischtime, swt.admittime, SECOND) / 86400.0) AS los_days
  FROM scores_with_tertile swt
)

SELECT
  tertile,
  COUNT(*) AS admissions_count,
  MIN(score) AS score_min,
  MAX(score) AS score_max,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS inhospital_mortality_percent,
  ROUND(100.0 * AVG(CAST(readmit_30d_flag AS FLOAT64)), 2) AS readmit_30d_percent
FROM readmit30_flag
GROUP BY tertile
ORDER BY tertile;