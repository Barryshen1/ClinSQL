WITH diag_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
pe_admissions AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pulmonary embol%'
),
risk_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    p.dod,
    dc.risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN diag_counts dc
    ON a.hadm_id = dc.hadm_id
  JOIN pe_admissions pe
    ON a.hadm_id = pe.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),
percentiles AS (
  SELECT
    PERCENTILE_CONT(risk_score, 0.75) OVER() AS p75
  FROM risk_scores
  LIMIT 1
),
target_cohort AS (
  SELECT
    rs.*,
    CASE WHEN p.dod IS NOT NULL
         AND DATE_DIFF(p.dod, rs.admittime, DAY) <= 90 THEN 1 ELSE 0 END AS mortality_90d,
    DATE_DIFF(rs.dischtime, rs.admittime, DAY) AS los
  FROM risk_scores rs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON rs.subject_id = p.subject_id
  CROSS JOIN percentiles pct
  WHERE rs.risk_score > pct.p75
),
aki_flags AS (
  SELECT DISTINCT
    d.hadm_id,
    1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute kidney injury%'
),
ards_flags AS (
  SELECT DISTINCT
    d.hadm_id,
    1 AS ards_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%adult respiratory distress syndrome%'
     OR LOWER(dd.long_title) LIKE '%ards%'
),
all_inpatients AS (
  SELECT
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, a.admittime, DAY) <= 90 THEN 1 ELSE 0 END AS mortality_90d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
all_inpatients_rates AS (
  SELECT
    AVG(IF(aki_all.aki_flag IS NOT NULL, 1, 0)) AS aki_rate_all_inpatients,
    AVG(IF(ards_all.ards_flag IS NOT NULL, 1, 0)) AS ards_rate_all_inpatients
  FROM all_inpatients ai
  LEFT JOIN aki_flags aki_all
    ON ai.hadm_id = aki_all.hadm_id
  LEFT JOIN ards_flags ards_all
    ON ai.hadm_id = ards_all.hadm_id
)
SELECT
  -- Target cohort metrics
  AVG(tc.risk_score) AS mean_risk_score_cohort,
  AVG(tc.mortality_90d) AS mortality_90d_rate_cohort,
  -- Survivors in cohort AKI/ARDS rates & LOS
  AVG(IF(tc.mortality_90d = 0, IF(aki.aki_flag IS NOT NULL, 1, 0), NULL)) AS aki_rate_survivors,
  AVG(IF(tc.mortality_90d = 0, IF(ards.ards_flag IS NOT NULL, 1, 0), NULL)) AS ards_rate_survivors,
  AVG(IF(tc.mortality_90d = 0, tc.los, NULL)) AS mean_los_survivors,
  -- All inpatient AKI/ARDS rates from summary (use MAX to bring through constant)
  MAX(air.aki_rate_all_inpatients) AS aki_rate_all_inpatients,
  MAX(air.ards_rate_all_inpatients) AS ards_rate_all_inpatients,
  -- Matched-profile risk percentile
  PERCENT_RANK() OVER (ORDER BY tc.risk_score) AS matched_profile_risk_percentile
FROM target_cohort tc
LEFT JOIN aki_flags aki
  ON tc.hadm_id = aki.hadm_id
LEFT JOIN ards_flags ards
  ON tc.hadm_id = ards.hadm_id
CROSS JOIN all_inpatients_rates air;