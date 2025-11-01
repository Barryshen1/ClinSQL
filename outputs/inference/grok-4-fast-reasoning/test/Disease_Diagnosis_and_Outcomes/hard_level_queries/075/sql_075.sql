WITH all_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 44 AND 54
),
ich_diagnoses AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'I61%')
     OR (icd_version = 9 AND icd_code IN ('430', '431', '432'))
),
ich_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.deathtime
  FROM all_admissions a
  INNER JOIN ich_diagnoses id ON a.subject_id = id.subject_id AND a.hadm_id = id.hadm_id
),
all_index AS (
  SELECT subject_id, hadm_id AS index_hadm_id, admittime AS index_admittime, 
         dischtime AS index_dischtime, hospital_expire_flag AS index_expire_flag
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM all_admissions
  )
  WHERE rn = 1
),
ich_index AS (
  SELECT subject_id, hadm_id AS index_hadm_id, admittime AS index_admittime, 
         dischtime AS index_dischtime, hospital_expire_flag AS index_expire_flag
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM ich_admissions
  )
  WHERE rn = 1
),
all_with_risk AS (
  SELECT ai.*, dc.drg_mortality AS risk_score
  FROM all_index ai
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc 
    ON ai.index_hadm_id = dc.hadm_id AND dc.drg_type = 'MS-DRG'
  WHERE dc.drg_mortality IS NOT NULL
),
ich_with_risk AS (
  SELECT ii.*, dc.drg_mortality AS risk_score
  FROM ich_index ii
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc 
    ON ii.index_hadm_id = dc.hadm_id AND dc.drg_type = 'MS-DRG'
  WHERE dc.drg_mortality IS NOT NULL
),
all_with_mort AS (
  SELECT awr.*, 
         CASE WHEN p.dod IS NOT NULL 
              AND DATE(p.dod) <= DATE_ADD(DATE(awr.index_admittime), INTERVAL 90 DAY) 
              THEN 1 ELSE 0 END AS mortality_90d
  FROM all_with_risk awr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON awr.subject_id = p.subject_id
),
ich_with_mort AS (
  SELECT iwr.*, 
         CASE WHEN p.dod IS NOT NULL 
              AND DATE(p.dod) <= DATE_ADD(DATE(iwr.index_admittime), INTERVAL 90 DAY) 
              THEN 1 ELSE 0 END AS mortality_90d
  FROM ich_with_risk iwr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON iwr.subject_id = p.subject_id
),
all_with_los AS (
  SELECT *, 
         CASE WHEN mortality_90d = 0 
              THEN DATE_DIFF(DATE(index_dischtime), DATE(index_admittime), DAY) 
              ELSE NULL END AS survivor_los
  FROM all_with_mort
),
ich_with_los AS (
  SELECT *, 
         CASE WHEN mortality_90d = 0 
              THEN DATE_DIFF(DATE(index_dischtime), DATE(index_admittime), DAY) 
              ELSE NULL END AS survivor_los
  FROM ich_with_mort
),
all_dist AS (
  SELECT risk_score, COUNT(*) AS freq
  FROM all_with_risk
  GROUP BY risk_score
),
all_cum AS (
  SELECT 
    risk_score,
    SUM(freq) OVER (ORDER BY risk_score ROWS UNBOUNDED PRECEDING) * 1.0 / 
    (SELECT COUNT(*) FROM all_with_risk) AS risk_percentile
  FROM all_dist
),
ich_with_risk_percentile AS (
  SELECT iwl.*, ac.risk_percentile
  FROM ich_with_los iwl
  LEFT JOIN all_cum ac ON iwl.risk_score = ac.risk_score
),
all_with_comp AS (
  SELECT awl.*,
         CASE WHEN EXISTS (
           SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
           WHERE icu.hadm_id = awl.index_hadm_id
         ) THEN 1 ELSE 0 END AS major_complication
  FROM all_with_los awl
),
ich_with_comp AS (
  SELECT iwrp.*,
         CASE WHEN EXISTS (
           SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
           WHERE icu.hadm_id = iwrp.index_hadm_id
         ) THEN 1 ELSE 0 END AS major_complication
  FROM ich_with_risk_percentile iwrp
),
ich_risk_stats AS (
  SELECT 
    q[OFFSET(1)] AS median_risk,
    q[OFFSET(0)] AS iqr_lower,
    q[OFFSET(2)] AS iqr_upper
  FROM (
    SELECT APPROX_QUANTILES(risk_score, 3) AS q
    FROM ich_with_comp
  ) sub
),
ich_mortality AS (
  SELECT AVG(mortality_90d) AS mortality_rate
  FROM ich_with_comp
),
ich_comp AS (
  SELECT AVG(CAST(major_complication AS FLOAT64)) AS comp_rate
  FROM ich_with_comp
),
ich_los AS (
  SELECT APPROX_QUANTILES(survivor_los, 1)[OFFSET(0)] AS median_los
  FROM ich_with_comp
  WHERE survivor_los IS NOT NULL
),
ich_percentile AS (
  SELECT APPROX_QUANTILES(risk_percentile, 1)[OFFSET(0)] AS median_percentile
  FROM ich_with_comp
  WHERE risk_percentile IS NOT NULL
),
all_comp AS (
  SELECT AVG(CAST(major_complication AS FLOAT64)) AS comp_rate
  FROM all_with_comp
),
all_los AS (
  SELECT APPROX_QUANTILES(survivor_los, 1)[OFFSET(0)] AS median_los
  FROM all_with_comp
  WHERE survivor_los IS NOT NULL
)
SELECT 
  'ICH cohort' AS cohort,
  irs.median_risk AS median_risk_score,
  irs.iqr_lower AS iqr_lower,
  irs.iqr_upper AS iqr_upper,
  im.mortality_rate AS `90-day mortality rate`,
  ic.comp_rate AS `major complication rate`,
  il.median_los AS `median survivor LOS (days)`,
  ip.median_percentile AS `matched risk percentile`
FROM ich_risk_stats irs, ich_mortality im, ich_comp ic, ich_los il, ich_percentile ip
UNION ALL
SELECT 
  'All females 44-54' AS cohort,
  NULL AS median_risk_score,
  NULL AS iqr_lower,
  NULL AS iqr_upper,
  NULL AS `90-day mortality rate`,
  ac.comp_rate AS `major complication rate`,
  al.median_los AS `median survivor LOS (days)`,
  NULL AS `matched risk percentile`
FROM all_comp ac, all_los al
ORDER BY cohort;