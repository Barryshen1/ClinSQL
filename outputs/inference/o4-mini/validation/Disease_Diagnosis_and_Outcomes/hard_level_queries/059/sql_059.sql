WITH
-- Placeholder risk scores
risk_scores AS (
  SELECT
    subject_id,
    hadm_id,
    0.0 AS risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- 1. DKA admissions, male, age 59-69
dka_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code    = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(dicd.long_title) LIKE '%ketoacidosis%'
),

-- 2. General age-matched male inpatients excluding DKA
general_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND NOT EXISTS (
      SELECT 1
      FROM dka_cohort d
      WHERE d.hadm_id = a.hadm_id
    )
),

-- 3. Flag 30-day mortality for DKA
with_mort_dka AS (
  SELECT
    d.*,
    rs.risk_score,
    CASE
      WHEN d.hospital_expire_flag = 1 THEN 1
      WHEN p.dod IS NOT NULL
           AND DATE_DIFF(DATE(p.dod), DATE(d.admittime), DAY) <= 30 THEN 1
      ELSE 0
    END AS died30
  FROM dka_cohort d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  LEFT JOIN risk_scores rs
    ON d.subject_id = rs.subject_id
   AND d.hadm_id    = rs.hadm_id
),

-- 4. Flag 30-day mortality for general cohort
with_mort_general AS (
  SELECT
    g.*,
    rs.risk_score,
    CASE
      WHEN g.hospital_expire_flag = 1 THEN 1
      WHEN p.dod IS NOT NULL
           AND DATE_DIFF(DATE(p.dod), DATE(g.admittime), DAY) <= 30 THEN 1
      ELSE 0
    END AS died30
  FROM general_cohort g
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON g.subject_id = p.subject_id
  LEFT JOIN risk_scores rs
    ON g.subject_id = rs.subject_id
   AND g.hadm_id    = rs.hadm_id
),

-- 5. AKI and ARDS admissions
aki_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code    = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%acute kidney injury%'
     OR d.icd_code LIKE '584%'
),
ards_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code = '51882'
),

-- 6. Summary statistics for each cohort
summary AS (
  SELECT
    'DKA' AS cohort,
    COUNT(*) AS n,
    AVG(risk_score) AS mean_risk_score,
    AVG(died30) AS mortality_30d,
    AVG(IF(w.hadm_id IN (SELECT hadm_id FROM aki_admissions), 1, 0)) AS aki_rate,
    AVG(IF(w.hadm_id IN (SELECT hadm_id FROM ards_admissions), 1, 0)) AS ards_rate,
    AVG(
      IF(w.hospital_expire_flag = 0,
         TIMESTAMP_DIFF(w.dischtime, w.admittime, DAY),
         NULL)
    ) AS mean_los_survivors
  FROM with_mort_dka w

  UNION ALL

  SELECT
    'General' AS cohort,
    COUNT(*) AS n,
    AVG(risk_score) AS mean_risk_score,
    AVG(died30) AS mortality_30d,
    AVG(IF(w.hadm_id IN (SELECT hadm_id FROM aki_admissions), 1, 0)) AS aki_rate,
    AVG(IF(w.hadm_id IN (SELECT hadm_id FROM ards_admissions), 1, 0)) AS ards_rate,
    AVG(
      IF(w.hospital_expire_flag = 0,
         TIMESTAMP_DIFF(w.dischtime, w.admittime, DAY),
         NULL)
    ) AS mean_los_survivors
  FROM with_mort_general w
),

-- 7. Percentile of each DKA risk_score within the general distribution
dka_percentiles AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.risk_score,
    (SELECT COUNT(*) FROM with_mort_general g WHERE g.risk_score <= d.risk_score) * 1.0
      / (SELECT COUNT(*) FROM with_mort_general) AS risk_percentile
  FROM with_mort_dka d
),

-- 8. Single-row summary of average DKA percentile
percent_summary AS (
  SELECT AVG(risk_percentile) AS avg_dka_risk_percentile
  FROM dka_percentiles
)

-- 9. Final output
SELECT
  s.*,
  ps.avg_dka_risk_percentile
FROM summary s
LEFT JOIN percent_summary ps
  ON s.cohort = 'DKA';