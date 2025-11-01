WITH 
-- Identify AMI patients
ami_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE '410.%'
        AND icd_version = 'ICD-9'
    )
),

-- Exclude patients with shock or respiratory failure
exclusion_criteria AS (
  SELECT DISTINCT 
    ce.subject_id,
    ce.hadm_id,
    ic.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  ON 
    ce.subject_id = ic.subject_id AND ce.hadm_id = ic.hadm_id
  WHERE 
    ce.itemid IN (220050, 220179)  
    AND ce.valuenum IS NOT NULL
),

-- Calculate LOS categories and mortality
los_mortality AS (
  SELECT 
    ap.hadm_id,
    ap.subject_id,
    ap.admittime,
    ap.dischtime,
    ap.hospital_expire_flag,
    DATE_DIFF(ap.dischtime, ap.admittime, DAY) AS los_days,
    COALESCE(s.curr_service, 'Unknown') AS discharge_destination
  FROM 
    ami_patients ap
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.services` s
  ON 
    ap.hadm_id = s.hadm_id AND 
    TIMESTAMP(ap.dischtime) = TIMESTAMP(s.transfertime)
  WHERE 
    ap.hadm_id NOT IN (SELECT hadm_id FROM exclusion_criteria)
)

SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1–3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4–7'
    WHEN los_days >= 8 THEN '≥8'
  END AS los_category,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  COUNT(*) AS total_patients,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los,
  discharge_destination
FROM 
  los_mortality
GROUP BY 
  los_category,
  discharge_destination
ORDER BY 
  los_category, 
  discharge_destination;