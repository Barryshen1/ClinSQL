WITH target_cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    COUNT(CASE 
      WHEN ce.itemid = 52 AND ce.valuenum < 65 THEN 1
      WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1
    END) AS composite_instability_events
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON i.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  LEFT JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (52, 220045)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(did.long_title) LIKE '%respiratory failure%'
  GROUP BY i.stay_id, i.hadm_id, i.intime, i.outtime, i.los, p.gender, p.anchor_age, a.hospital_expire_flag
),
general_cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    COUNT(CASE 
      WHEN ce.itemid = 52 AND ce.valuenum < 65 THEN 1
      WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1
    END) AS composite_instability_events
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (52, 220045)
  GROUP BY i.stay_id, i.hadm_id, i.intime, i.outtime, i.los, p.gender, p.anchor_age, a.hospital_expire_flag
),
target_metrics AS (
  SELECT
    PERCENTILE_CONT(composite_instability_events, 0.25) AS p25_instability,
    PERCENTILE_CONT(composite_instability_events, 0.5) AS median_instability,
    PERCENTILE_CONT(composite_instability_events, 0.75) AS p75_instability,
    PERCENTILE_CONT(composite_instability_events, 0.75) - PERCENTILE_CONT(composite_instability_events, 0.25) AS iqr_instability,
    AVG(composite_instability_events) AS mean_instability,
    AVG(los) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM target_cohort
  WHERE composite_instability_events IS NOT NULL
),
general_metrics AS (
  SELECT
    PERCENTILE_CONT(composite_instability_events, 0.25) AS p25_instability,
    PERCENTILE_CONT(composite_instability_events, 0.5) AS median_instability,
    PERCENTILE_CONT(composite_instability_events, 0.75) AS p75_instability,
    PERCENTILE_CONT(composite_instability_events, 0.75) - PERCENTILE_CONT(composite_instability_events, 0.25) AS iqr_instability,
    AVG(composite_instability_events) AS mean_instability,
    AVG(los) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM general_cohort
  WHERE composite_instability_events IS NOT NULL
)
SELECT
  'Target Cohort (Male, 82-92, Respiratory Failure)' AS cohort,
  t.p25_instability,
  t.median_instability,
  t.p75_instability,
  t.iqr_instability,
  t.mean_instability,
  t.mean_los,
  t.mortality_rate
FROM target_metrics t
UNION ALL
SELECT
  'General ICU Cohort' AS cohort,
  g.p25_instability,
  g.median_instability,
  g.p75_instability,
  g.iqr_instability,
  g.mean_instability,
  g.mean_los,
  g.mortality_rate
FROM general_metrics g;