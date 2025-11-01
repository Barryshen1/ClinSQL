WITH respiratory_failure_patients AS (
  SELECT DISTINCT i.stay_id, i.subject_id, i.intime, i.los, p.anchor_age, p.gender, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON d.icd_code = d_diag.icd_code AND d.icd_version = d_diag.icd_version
  WHERE p.anchor_age BETWEEN 85 AND 95
    AND p.gender = 'M'
    AND LOWER(d_diag.long_title) LIKE '%acute respiratory failure%'
),

vital_signs_first_24h AS (
  SELECT 
    rfp.stay_id,
    ce.itemid,
    ce.valuenum,
    di.label,
    ce.charttime
  FROM respiratory_failure_patients rfp
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON rfp.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.charttime >= rfp.intime 
    AND ce.charttime < TIMESTAMP_ADD(rfp.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND di.label IN ('Heart Rate', 'Systolic BP', 'Respiratory Rate', 'Temperature', 'SpO2')
),

vital_sign_stats AS (
  SELECT 
    label,
    AVG(valuenum) AS mean_val,
    STDDEV(valuenum) AS std_val
  FROM vital_signs_first_24h
  GROUP BY label
),

patient_vital_zscores AS (
  SELECT 
    vsf.stay_id,
    vsf.label,
    (vsf.valuenum - vs.mean_val) / vs.std_val AS z_score
  FROM vital_signs_first_24h vsf
  JOIN vital_sign_stats vs ON vsf.label = vs.label
),

patient_instability_score AS (
  SELECT 
    stay_id,
    SUM(ABS(z_score)) AS raw_instability_score
  FROM patient_vital_zscores
  GROUP BY stay_id
),

scaled_instability AS (
  SELECT 
    stay_id,
    raw_instability_score,
    (raw_instability_score - MIN(raw_instability_score) OVER()) * 100.0 / 
    (MAX(raw_instability_score) OVER() - MIN(raw_instability_score) OVER()) AS scaled_instability_score
  FROM patient_instability_score
),

percentile_ranking AS (
  SELECT 
    stay_id,
    scaled_instability_score,
    PERCENT_RANK() OVER (ORDER BY scaled_instability_score) AS percentile_rank
  FROM scaled_instability
),

quartile_analysis AS (
  SELECT 
    stay_id,
    scaled_instability_score,
    NTILE(4) OVER (ORDER BY scaled_instability_score) AS quartile,
    rfp.los,
    rfp.hospital_expire_flag
  FROM scaled_instability si
  JOIN respiratory_failure_patients rfp ON si.stay_id = rfp.stay_id
)

SELECT 
  (SELECT MAX(percentile_rank) FROM percentile_ranking WHERE scaled_instability_score >= 85) AS percentile_rank_of_85,
  AVG(CASE WHEN quartile = 4 THEN los END) AS avg_los_top_quartile,
  AVG(CASE WHEN quartile = 4 THEN hospital_expire_flag END) AS mortality_top_quartile
FROM quartile_analysis;