WITH target_population AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(did.long_title) LIKE '%asthma%exacerbation%'
    AND d.icd_version = 10
),

lab_events_72h AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.flag,
    dl.label
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  JOIN target_population tp
    ON le.hadm_id = tp.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= tp.admittime
    AND le.charttime <= DATETIME_ADD(tp.admittime, INTERVAL 72 HOUR)
    AND le.flag IN ('Abnormal', 'High', 'Low')
),

lab_instability_score AS (
  SELECT
    hadm_id,
    COUNT(*) AS critical_lab_events
  FROM lab_events_72h
  GROUP BY hadm_id
),

percentile_90 AS (
  SELECT
    PERCENTILE_CONT(critical_lab_events, 0.9) AS p90_score
  FROM lab_instability_score
),

top_decile AS (
  SELECT
    lis.hadm_id,
    lis.critical_lab_events,
    tp.hospital_expire_flag,
    ic.los AS icu_los
  FROM lab_instability_score lis
  JOIN target_population tp ON lis.hadm_id = tp.hadm_id
  JOIN physionet-data.mimiciv_3_1_icu.icustays ic
    ON tp.hadm_id = ic.hadm_id
  CROSS JOIN percentile_90 p90
  WHERE lis.critical_lab_events >= p90.p90_score
  QUALIFY ROW_NUMBER() OVER (PARTITION BY lis.hadm_id ORDER BY ic.intime) = 1
),

overall_population AS (
  SELECT
    lis.critical_lab_events,
    tp.hospital_expire_flag,
    ic.los AS icu_los
  FROM lab_instability_score lis
  JOIN target_population tp ON lis.hadm_id = tp.hadm_id
  JOIN physionet-data.mimiciv_3_1_icu.icustays ic
    ON tp.hadm_id = ic.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY lis.hadm_id ORDER BY ic.intime) = 1
)

SELECT
  -- 90th percentile value
  (SELECT p90_score FROM percentile_90) AS p90_lab_instability_score,

  -- Top decile metrics
  COUNT(top.hadm_id) AS top_decile_n,
  AVG(CAST(top.hospital_expire_flag AS FLOAT64)) AS top_decile_mortality,
  AVG(top.icu_los) AS top_decile_mean_los,
  AVG(top.critical_lab_events) AS top_decile_avg_critical_labs,

  -- Overall population metrics for comparison
  COUNT(overall.hadm_id) AS overall_n,
  AVG(CAST(overall.hospital_expire_flag AS FLOAT64)) AS overall_mortality,
  AVG(overall.icu_los) AS overall_mean_los,
  AVG(overall.critical_lab_events) AS overall_avg_critical_labs

FROM top_decile top
CROSS JOIN overall_population overall;