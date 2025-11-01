WITH cohort AS (
  -- Define asthma exacerbation cohort: males 52-62 with primary J45/J46 (ICD-9/10)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    DATE_ADD(a.admittime, INTERVAL 3 DAY) AS window_end,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND d.seq_num = 1
    AND (
      (d.icd_version = '10' AND (d.icd_code LIKE 'J45%' OR d.icd_code = 'J46')) OR
      (d.icd_version = '9' AND d.icd_code LIKE '493%')
    )
),

lab_critical_events AS (
  -- Critical labs within 72h: filter key itemids and abnormal values
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    l.flag,
    di.label
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON l.itemid = di.itemid
  INNER JOIN cohort c 
    ON l.subject_id = c.subject_id 
    AND CAST(l.hadm_id AS STRING) = c.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime <= c.window_end
  WHERE l.valuenum IS NOT NULL
    AND (l.flag = 'abnormal' OR 
         (l.valuenum < COALESCE(l.ref_range_lower, 0) OR l.valuenum > COALESCE(l.ref_range_upper, 999)))
    AND di.label IN (
      'Potassium', 'Sodium', 'Magnesium', 'BUN', 'Creatinine', 
      'WBC', 'pH (Blood gas)', 'PaO2 (Pulmonary artery)', 'PaCO2 (Pulmonary artery)', 'Bicarbonate, Total - Blood'
    )  -- Exact labels from d_labitems
),

lab_instability AS (
  -- Compute score: count unique critical lab types per admission (dedup by label and day)
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT CONCAT(label, DATE(charttime))) AS critical_lab_events,
    COUNT(DISTINCT label) AS instability_score  -- Score as # unique abnormal lab types
  FROM lab_critical_events
  GROUP BY subject_id, hadm_id
),

scored_cohort AS (
  SELECT 
    c.*,
    COALESCE(li.instability_score, 0) AS instability_score,
    COALESCE(li.critical_lab_events, 0) AS raw_critical_events
  FROM cohort c
  LEFT JOIN lab_instability li ON c.subject_id = li.subject_id AND c.hadm_id = li.hadm_id
),

percentile_calc AS (
  SELECT 
    PERCENTILE_CONT(0.9) OVER () AS p90_score
  FROM scored_cohort
),

top_decile_agg AS (
  SELECT 
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS top_mortality,
    AVG(los_days) AS top_los,
    AVG(raw_critical_events) AS top_events,
    COUNT(*) AS top_n
  FROM scored_cohort
  CROSS JOIN percentile_calc
  WHERE instability_score >= p90_score
),

control AS (
  -- Age-matched males (any admission, exclude asthma cohort)
  SELECT 
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    0 AS raw_critical_events
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.hadm_id NOT IN (SELECT hadm_id FROM cohort)
),

control_agg AS (
  SELECT 
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS control_mortality,
    AVG(los_days) AS control_los,
    AVG(raw_critical_events) AS control_events,
    COUNT(*) AS control_n
  FROM control
)

SELECT 
  -- 90th percentile
  pc.p90_score AS p90_instability_score,
  
  -- Top decile metrics
  t.top_mortality AS top_decile_mortality,
  t.top_los AS top_decile_mean_los,
  t.top_events AS top_decile_avg_critical_events,
  t.top_n AS top_decile_n,
  
  -- Control metrics
  c.control_mortality AS control_mortality,
  c.control_los AS control_mean_los,
  c.control_events AS control_avg_critical_events,
  c.control_n AS control_n,
  
  -- Comparisons
  (t.top_mortality / NULLIF(c.control_mortality, 0)) AS mortality_ratio_vs_control,
  (t.top_los / NULLIF(c.control_los, 0)) AS los_ratio_vs_control

FROM percentile_calc pc
CROSS JOIN top_decile_agg t
CROSS JOIN control_agg c;