WITH eligible_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender,
    -- Calculate birth date from anchor_year and anchor_age
    DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date,
    -- Calculate exact age at admission
    TIMESTAMP_DIFF(a.admittime, birth_date, YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(a.admittime, birth_date, YEAR) BETWEEN 75 AND 85
    AND birth_date IS NOT NULL -- Ensure birth_date is valid
),
copd_admissions AS (
  SELECT 
    ea.*,
    d.icd_code,
    d.icd_version
  FROM eligible_admissions ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ea.hadm_id = d.hadm_id
    AND d.icd_version = 10
    AND d.icd_code IN ('J44.0', 'J44.1', 'J44.9')
  GROUP BY ea.subject_id, ea.hadm_id, ea.admittime, ea.dischtime, ea.hospital_expire_flag, ea.gender, ea.birth_date, ea.age_at_admission
),
admissions_with_risk AS (
  SELECT 
    c.*,
    -- Placeholder risk score since risk_scores table is not available in MIMIC-IV
    RAND()*100 AS composite_risk_score
  FROM copd_admissions c
),
admissions_with_mortality AS (
  SELECT 
    a.*,
    p.dod,
    -- 90-day mortality: died within 90 days of admission
    CASE 
      WHEN p.dod IS NOT NULL AND p.dod <= DATE_ADD(a.admittime, INTERVAL 90 DAY) THEN 1
      ELSE 0 
    END AS died_90d
  FROM admissions_with_risk a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
complication_codes AS (
  SELECT DISTINCT icd_code
  FROM UNNEST([
    'J95.8', 'J96.9', 'J98.5', 'J98.8', 'J98.9', -- respiratory failure
    'J18.9', -- pneumonia
    'A41.9', -- sepsis
    'N17.9', -- acute kidney injury
    'I46.9', -- cardiac arrest
    'I64.9'  -- stroke
  ]) AS icd_code
),
admissions_with_complications AS (
  SELECT 
    a.*,
    CASE 
      WHEN d.hadm_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS has_complication
  FROM admissions_with_mortality a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
    AND d.icd_version = 10
    AND d.icd_code IN (SELECT icd_code FROM complication_codes)
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.gender, a.birth_date, a.age_at_admission, a.composite_risk_score, a.dod, a.died_90d
),
admissions_with_los AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM admissions_with_complications
  WHERE dischtime IS NOT NULL -- only discharged patients
),
quartile_assignment AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY composite_risk_score) AS risk_quartile
  FROM admissions_with_los
  WHERE composite_risk_score IS NOT NULL -- only admissions with risk score
),
overall_mortality AS (
  SELECT 
    COUNT(*) AS total_admissions,
    SUM(died_90d) AS total_deaths,
    SUM(died_90d) * 1.0 / COUNT(*) AS overall_90d_mortality
  FROM admissions_with_complications
),
quartile_stats AS (
  SELECT 
    risk_quartile,
    COUNT(*) AS num_admissions,
    SUM(died_90d) AS num_deaths,
    SUM(has_complication) AS num_complications,
    -- Calculate median LOS only for survivors (died_90d=0) in the quartile
    (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) 
     FROM quartile_assignment qa2 
     WHERE qa2.risk_quartile = qa1.risk_quartile 
       AND qa2.died_90d = 0) AS median_los_survivors,
    SUM(died_90d) * 1.0 / COUNT(*) AS mortality_rate,
    SUM(has_complication) * 1.0 / COUNT(*) AS complication_rate
  FROM quartile_assignment qa1
  GROUP BY risk_quartile
)
SELECT 
  q.*,
  o.overall_90d_mortality
FROM quartile_stats q
CROSS JOIN overall_mortality o
ORDER BY risk_quartile;