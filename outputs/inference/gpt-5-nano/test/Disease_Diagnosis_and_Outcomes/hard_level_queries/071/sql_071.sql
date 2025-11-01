WITH index_population AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    CASE
      WHEN p.dod IS NOT NULL
           AND DATE(p.dod) <= DATE(TIMESTAMP_ADD(a.admittime, INTERVAL 90 DAY))
      THEN 1 ELSE 0
    END AS mort_90d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 68 AND 78
    -- AMI during admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
              (d.icd_version = 9 AND d.icd_code LIKE '410%')
              OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
            )
    )
    -- Require an ICU stay for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      WHERE icu.subject_id = a.subject_id
        AND icu.hadm_id = a.hadm_id
    )
),

comorb_flags AS (
  SELECT
    ip.subject_id,
    ip.hadm_id,
    MAX(CASE WHEN d.icd_version = 9 AND d.icd_code LIKE '410%' THEN 1 ELSE 0 END) AS has_mi,
    MAX(CASE WHEN d.icd_version = 9 AND (d.icd_code LIKE '414%' OR d.icd_code LIKE '428%') THEN 1 ELSE 0 END) AS has_chf,
    MAX(CASE WHEN d.icd_version = 9 AND (
              d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR
              d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '435%' OR
              d.icd_code LIKE '436%' OR d.icd_code LIKE '437%' OR d.icd_code LIKE '438%'
            ) THEN 1 ELSE 0 END) AS has_cva,
    MAX(CASE WHEN d.icd_version = 9 AND (
              d.icd_code LIKE '290%' OR d.icd_code LIKE 'F02%' OR d.icd_code LIKE 'F03%'
            ) THEN 1 ELSE 0 END) AS has_dementia,
    MAX(CASE WHEN d.icd_version = 9 AND (
              d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE 'J44%'
            ) THEN 1 ELSE 0 END) AS has_copd,
    MAX(CASE WHEN d.icd_version = 9 AND d.icd_code LIKE '250%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.icd_version = 9 AND (
              d.icd_code LIKE '585%' OR d.icd_code LIKE '580%' OR d.icd_code LIKE '581%' OR
              d.icd_code LIKE '582%' OR d.icd_code LIKE '583%'
            ) THEN 1 ELSE 0 END) AS has_renal,
    MAX(CASE WHEN d.icd_version = 9 AND (
              d.icd_code LIKE '571%' OR d.icd_code LIKE 'K70%'
            ) THEN 1 ELSE 0 END) AS has_liver,
    MAX(CASE WHEN d.icd_version = 9 AND (
              d.icd_code LIKE '140%' OR d.icd_code LIKE '141%' OR d.icd_code LIKE '142%' OR
              d.icd_code LIKE '143%' OR d.icd_code LIKE '144%' OR d.icd_code LIKE '145%' OR
              d.icd_code LIKE '146%' OR d.icd_code LIKE '147%' OR d.icd_code LIKE '148%' OR d.icd_code LIKE '149%'
            ) THEN 1 ELSE 0 END) AS has_cancer
  FROM index_population ip
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.subject_id = ip.subject_id AND d.hadm_id = ip.hadm_id
  GROUP BY ip.subject_id, ip.hadm_id
),

risk_score AS (
  SELECT cf.subject_id,
         cf.hadm_id,
         COALESCE(cf.has_mi, 0)
         + COALESCE(cf.has_chf, 0)
         + COALESCE(cf.has_cva, 0)
         + COALESCE(cf.has_dementia, 0)
         + COALESCE(cf.has_copd, 0)
         + COALESCE(cf.has_diabetes, 0)
         + COALESCE(cf.has_renal, 0)
         + COALESCE(cf.has_liver, 0)
         + COALESCE(cf.has_cancer, 0) AS risk_score
  FROM comorb_flags cf
),

major_complications AS (
  SELECT
    ip.subject_id,
    ip.hadm_id,
    MAX(CASE WHEN d.icd_version = 9 AND d.icd_code LIKE '584%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN d.icd_version = 9 AND d.icd_code LIKE '518%' THEN 1 ELSE 0 END) AS has_resp_failure,
    MAX(CASE WHEN d.icd_version = 9 AND d.icd_code LIKE '785%' THEN 1 ELSE 0 END) AS has_shock
  FROM index_population ip
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.subject_id = ip.subject_id AND d.hadm_id = ip.hadm_id
  GROUP BY ip.subject_id, ip.hadm_id
),

index_metrics AS (
  SELECT
    ip.subject_id,
    ip.hadm_id,
    rc.risk_score,
    ip.mort_90d,
    TIMESTAMP_DIFF(ip.dischtime, ip.admittime, SECOND)/86400.0 AS los_days
  FROM index_population ip
  JOIN risk_score rc
    ON rc.subject_id = ip.subject_id AND rc.hadm_id = ip.hadm_id
),

general_inpatients AS (
  SELECT
    a.subject_id AS subj,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 68 AND 78
    -- Exclude the index AMI/ICU subset
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
        AND (
              (d.icd_version = 9 AND d.icd_code LIKE '410%')
              OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
            )
    )
),

comparator_risk_scores AS (
  SELECT
    g.subj,
    g.hadm_id,
    g.dischtime,
    g.admittime,
    g.dod,
    rs.risk_score
  FROM general_inpatients g
  LEFT JOIN risk_score rs
    ON rs.subject_id = g.subj AND rs.hadm_id = g.hadm_id
),

comparator_metrics AS (
  SELECT
    (SELECT COUNT(*) FROM comparator_risk_scores) AS total_general_inpatients,
    (SELECT AVG(CASE WHEN dod IS NULL OR DATE(dod) > DATE(TIMESTAMP_ADD(admittime, INTERVAL 90 DAY)) THEN 1 ELSE 0 END)
       FROM comparator_risk_scores) AS survivor_rate_90d,
    (SELECT APPROX_QUANTILES(TIMESTAMP_DIFF(dischtime, admittime, SECOND)/86400.0, 100)[OFFSET(50)]
       FROM comparator_risk_scores) AS comparator_general_inpatients_median_los
),

-- general inpatient risk distribution for percentile calculation
general_inpatients_risk AS (
  SELECT rs.subject_id, rs.hadm_id, rs.risk_score
  FROM risk_score rs
  JOIN general_inpatients gi ON gi.subj = rs.subject_id AND gi.hadm_id = rs.hadm_id
),
index_with_risk AS (
  SELECT i.subject_id, i.hadm_id, rs.risk_score AS index_risk
  FROM index_metrics i
  JOIN risk_score rs ON rs.subject_id = i.subject_id AND rs.hadm_id = i.hadm_id
),
risk_percentile AS (
  SELECT iw.subject_id, iw.hadm_id, iw.index_risk,
         SAFE_DIVIDE(
           (SELECT COUNT(*) FROM general_inpatients_risk gr WHERE gr.risk_score <= iw.index_risk),
           (SELECT COUNT(*) FROM general_inpatients_risk)
         ) AS risk_percentile_in_general_inpatients
  FROM index_with_risk iw
)

SELECT
  -- 1) index population risk distribution (median, Q1, Q3)
  (SELECT
     risk_r.sk
     FROM (SELECT r.risk_score AS sk FROM risk_score r) AS risk_rsk
  ) AS dummy, -- placeholder to illustrate structure (will be replaced below)

  -- Use proper numeric references with explicit aliasing to avoid STRUCT issue
  (SELECT APPROX_QUANTILES(r.risk_score, 100)[OFFSET(49)]
     FROM risk_score r) AS risk_median,
  (SELECT APPROX_QUANTILES(r.risk_score, 100)[OFFSET(24)]
     FROM risk_score r) AS risk_q1,
  (SELECT APPROX_QUANTILES(r.risk_score, 100)[OFFSET(75)]
     FROM risk_score r) AS risk_q3,
  -- 2) index 90-day mortality
  (SELECT AVG(mort_90d) FROM index_population) AS mortality_90d_rate,
  -- 3) major complications rate
  (SELECT AVG(CASE WHEN has_aki = 1 OR has_resp_failure = 1 OR has_shock = 1 THEN 1 ELSE 0 END)
     FROM major_complications) AS major_complications_rate,
  -- 4) survivor LOS median for index survivors
  (SELECT
     APPROX_QUANTILES(TIMESTAMP_DIFF(ip.dischtime, ip.admittime, SECOND)/86400.0, 100)[OFFSET(50)]
     FROM index_population ip WHERE ip.mort_90d = 0) AS survivor_los_median_days,
  -- 5) comparator metrics
  (SELECT survivor_rate_90d FROM comparator_metrics) AS comparator_survivor_rate_90d,
  (SELECT comparator_general_inpatients_median_los FROM comparator_metrics) AS comparator_general_inpatients_median_los_days,
  -- 6) index risk percentile within general inpatients
  (SELECT risk_percentile_in_general_inpatients FROM risk_percentile LIMIT 1) AS risk_percentile_in_general_inpatients
;