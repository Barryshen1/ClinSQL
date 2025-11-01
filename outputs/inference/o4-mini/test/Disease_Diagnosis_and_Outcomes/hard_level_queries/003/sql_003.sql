WITH pe_cohort AS (
  -- Female patients aged 70-80 with pulmonary embolism
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    COALESCE(a.deathtime, DATETIME(p.dod)) AS deathtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code    = dicd.icd_code
     AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND LOWER(dicd.long_title) LIKE '%pulmonary embol%'
),
risk_scores AS (
  -- Compute comorbidity-count proxy risk score and assign quintiles
  SELECT
    pc.*,
    COUNT(DISTINCT d.icd_code) AS risk_score
  FROM
    pe_cohort pc
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON pc.subject_id = d.subject_id
     AND pc.hadm_id    = d.hadm_id
  GROUP BY
    pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime, pc.deathtime, pc.anchor_age
),
risk_quintiles AS (
  SELECT
    rs.*,
    NTILE(5) OVER (ORDER BY rs.risk_score) AS risk_quintile
  FROM
    risk_scores rs
),
outcomes AS (
  SELECT
    rq.subject_id,
    rq.hadm_id,
    rq.admittime,
    rq.dischtime,
    rq.deathtime,
    rq.anchor_age,
    rq.risk_score,
    rq.risk_quintile,
    -- died within 90 days?
    CASE
      WHEN DATE_DIFF(DATE(rq.deathtime), DATE(rq.admittime), DAY) <= 90 THEN 1
      ELSE 0
    END AS died_90d,
    -- AKI flag
    MAX(CASE WHEN LOWER(dicd.long_title) LIKE '%acute kidney injury%' THEN 1 ELSE 0 END)
      OVER (PARTITION BY rq.hadm_id) AS has_aki,
    -- ARDS flag
    MAX(CASE WHEN LOWER(dicd.long_title) LIKE '%acute respiratory distress syndrome%' THEN 1 ELSE 0 END)
      OVER (PARTITION BY rq.hadm_id) AS has_ards,
    -- LOS in days
    DATE_DIFF(DATE(rq.dischtime), DATE(rq.admittime), DAY) AS los
  FROM
    risk_quintiles rq
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON rq.subject_id = d.subject_id
     AND rq.hadm_id    = d.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code    = dicd.icd_code
     AND d.icd_version = dicd.icd_version
),
overall_mort AS (
  -- Overall 90-day mortality across the pulmonary embolism cohort
  SELECT
    SAFE_DIVIDE(SUM(died_90d), COUNT(*)) AS overall_90d_mort
  FROM
    outcomes
)
SELECT
  o.risk_quintile,
  COUNT(*) AS n_in_quintile,
  SAFE_DIVIDE(SUM(o.died_90d), COUNT(*)) AS mort_90d,
  om.overall_90d_mort,
  SAFE_DIVIDE(SUM(o.has_aki), COUNT(*)) AS aki_rate,
  SAFE_DIVIDE(SUM(o.has_ards), COUNT(*)) AS ards_rate,
  -- median LOS among survivors (died_90d = 0)
  APPROX_QUANTILES(IF(o.died_90d = 0, o.los, NULL), 2)[OFFSET(1)] AS median_los_survivors
FROM
  outcomes o
  CROSS JOIN overall_mort om
GROUP BY
  o.risk_quintile,
  om.overall_90d_mort
ORDER BY
  o.risk_quintile;