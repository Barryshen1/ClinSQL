WITH pe_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    p.dod,
    -- crude risk score = number of unique diagnosis codes for this admission
    COUNT(DISTINCT CONCAT(d2.icd_code, '-', d2.icd_version)) AS risk_score,
    -- outcome flags
    CASE 
      WHEN p.dod IS NOT NULL 
       AND DATETIME_DIFF(p.dod, a.admittime, DAY) <= 90 THEN 1 ELSE 0 
    END AS mort90_flag,
    MAX(CASE 
      WHEN (d3.icd_version = 9 AND d3.icd_code LIKE '584%')
        OR (d3.icd_version = 10 AND d3.icd_code LIKE 'N17%')
      THEN 1 ELSE 0 END) AS aki_flag,
    MAX(CASE 
      WHEN (d3.icd_version = 9 AND d3.icd_code = '51882')
        OR (d3.icd_version = 10 AND d3.icd_code = 'J80')
      THEN 1 ELSE 0 END) AS ards_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- join for PE selection
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
  -- join again for comorbidity count
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  -- join again for AKI/ARDS detection
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
    ON a.hadm_id = d3.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND (
      (d1.icd_version = 9 AND d1.icd_code LIKE '4151%')
      OR (d1.icd_version = 10 AND d1.icd_code LIKE 'I26%')
    )
  GROUP BY a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, p.dod, mort90_flag
),
pe_quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM pe_cohort
),
pe_summary AS (
  SELECT
    risk_quintile,
    AVG(mort90_flag) AS pe_mort90_rate,
    AVG(aki_flag) AS aki_rate,
    AVG(ards_flag) AS ards_rate,
    APPROX_QUANTILES(IF(mort90_flag = 0, los_days, NULL), 100)[OFFSET(50)] AS median_survivor_los
  FROM pe_quintiles
  GROUP BY risk_quintile
),
general_female AS (
  SELECT
    AVG(CASE 
      WHEN p.dod IS NOT NULL 
           AND DATETIME_DIFF(p.dod, a.admittime, DAY) <= 90 THEN 1 ELSE 0 END) AS general_mort90_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
)
SELECT
  s.risk_quintile,
  s.pe_mort90_rate,
  g.general_mort90_rate,
  s.aki_rate,
  s.ards_rate,
  s.median_survivor_los
FROM pe_summary s
CROSS JOIN general_female g
ORDER BY risk_quintile;