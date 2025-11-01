WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.deathtime, 
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age, 
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
),
hf_cohort AS (
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = c.hadm_id
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '428%')
            OR
            (d.icd_version = 10 AND (
              d.icd_code LIKE 'I50%' 
              OR d.icd_code = 'I11.0' 
              OR d.icd_code LIKE 'I13.0%' 
              OR d.icd_code LIKE 'I13.2%'
            ))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_hf
  FROM cohort c
),
filtered_cohort AS (
  SELECT * 
  FROM hf_cohort 
  WHERE has_hf = 1
),
aki_cohort AS (
  SELECT 
    fc.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = fc.hadm_id
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '584%')
            OR
            (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
          )
      ) THEN 1 
      ELSE 0 
    END AS has_aki
  FROM filtered_cohort fc
),
ards_cohort AS (
  SELECT 
    ac.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = ac.hadm_id
          AND (
            (d.icd_version = 9 AND (d.icd_code = '518.5' OR d.icd_code LIKE '518.8%'))
            OR
            (d.icd_version = 10 AND (d.icd_code = 'J80' OR d.icd_code LIKE 'J96.0%'))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_ards
  FROM aki_cohort ac
),
drg_cohort AS (
  SELECT 
    rc.*,
    dc.drg_mortality AS risk_score
  FROM ards_cohort rc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc 
    ON rc.hadm_id = dc.hadm_id 
    AND dc.drg_type = 'MS'
),
deaths AS (
  SELECT 
    TIMESTAMP_DIFF(deathtime, admittime, DAY) AS survival_days
  FROM drg_cohort
  WHERE hospital_expire_flag = 1 
    AND deathtime IS NOT NULL
),
risk_dist AS (
  SELECT risk_score
  FROM drg_cohort
  WHERE risk_score IS NOT NULL
)
SELECT 
  (SELECT COUNT(*) FROM drg_cohort) AS total_admissions,
  (SELECT SUM(hospital_expire_flag) FROM drg_cohort) AS num_deaths,
  (SELECT ROUND(AVG(hospital_expire_flag) * 100, 2) FROM drg_cohort) AS mortality_rate_pct,
  (SELECT ROUND(SUM(has_aki) * 100.0 / COUNT(*), 2) FROM drg_cohort) AS aki_rate_pct,
  (SELECT ROUND(SUM(has_ards) * 100.0 / COUNT(*), 2) FROM drg_cohort) AS ards_rate_pct,
  (SELECT PERCENTILE_CONT(survival_days, 0.5) FROM deaths) AS median_survival_days,
  (SELECT MIN(risk_score) FROM risk_dist) AS risk_min,
  (SELECT PERCENTILE_CONT(risk_score, 0.25) FROM risk_dist) AS risk_p25,
  (SELECT PERCENTILE_CONT(risk_score, 0.5) FROM risk_dist) AS risk_median,
  (SELECT PERCENTILE_CONT(risk_score, 0.75) FROM risk_dist) AS risk_p75,
  (SELECT PERCENTILE_CONT(risk_score, 0.9) FROM risk_dist) AS risk_p90,
  (SELECT MAX(risk_score) FROM risk_dist) AS risk_max;