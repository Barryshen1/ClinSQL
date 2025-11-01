WITH respiratory_failure AS (
  SELECT 
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%respiratory failure%'
),

respiratory_icu AS (
  SELECT 
    r.subject_id,
    r.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM respiratory_failure r
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON r.subject_id = i.subject_id AND r.hadm_id = i.hadm_id
),

patient_details AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
),

specific_group AS (
  SELECT 
    ri.subject_id,
    ri.hadm_id,
    ri.stay_id,
    ri.intime,
    ri.outtime,
    ri.los
  FROM respiratory_icu ri
  JOIN patient_details pd ON ri.subject_id = pd.subject_id
  WHERE pd.gender = 'M'
    AND pd.anchor_age BETWEEN 40 AND 50
),

mortality_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

hypotensive_counts AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS hypotensive_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN respiratory_icu ri ON c.stay_id = ri.stay_id
  WHERE c.itemid = 52
    AND c.valuenum < 65
    AND c.charttime BETWEEN ri.intime AND ri.intime + INTERVAL 48 HOUR
  GROUP BY c.stay_id
),

tachycardic_counts AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS tachycardic_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN respiratory_icu ri ON c.stay_id = ri.stay_id
  WHERE c.itemid = 211
    AND c.valuenum > 100
    AND c.charttime BETWEEN ri.intime AND ri.intime + INTERVAL 48 HOUR
  GROUP BY c.stay_id
),

burden_data AS (
  SELECT 
    ri.stay_id,
    COALESCE(hc.hypotensive_count, 0) AS hypotensive_count,
    COALESCE(tc.tachycardic_count, 0) AS tachycardic_count,
    (COALESCE(hc.hypotensive_count, 0) + COALESCE(tc.tachycardic_count, 0)) AS vii_count
  FROM respiratory_icu ri
  LEFT JOIN hypotensive_counts hc ON ri.stay_id = hc.stay_id
  LEFT JOIN tachycardic_counts tc ON ri.stay_id = tc.stay_id
),

specific_group_vii AS (
  SELECT 
    bg.vii_count,
    bg.hypotensive_count,
    bg.tachycardic_count,
    ri.los,
    md.hospital_expire_flag
  FROM burden_data bg
  JOIN specific_group sg ON bg.stay_id = sg.stay_id
  JOIN mortality_data md ON sg.subject_id = md.subject_id AND sg.hadm_id = md.hadm_id
  JOIN respiratory_icu ri ON bg.stay_id = ri.stay_id
),

other_group_vii AS (
  SELECT 
    bg.vii_count,
    bg.hypotensive_count,
    bg.tachycardic_count,
    ri.los,
    md.hospital_expire_flag
  FROM burden_data bg
  JOIN respiratory_icu ri ON bg.stay_id = ri.stay_id
  JOIN mortality_data md ON ri.subject_id = md.subject_id AND ri.hadm_id = md.hadm_id
  WHERE NOT EXISTS (
    SELECT 1 
    FROM specific_group sg 
    WHERE sg.stay_id = ri.stay_id
  )
)

SELECT 
  'Specific Group (Male 40-50)' AS group_type,
  STDDEV(vii_count) AS std_dev_vii,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY vii_count) AS p25_vii,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vii_count) AS p50_vii,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY vii_count) AS p75_vii,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY vii_count) AS p95_vii,
  AVG(hypotensive_count) AS avg_hypotensive,
  AVG(tachycardic_count) AS avg_tachycardic,
  AVG(los) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM specific_group_vii

UNION ALL

SELECT 
  'Other Respiratory Failure Patients' AS group_type,
  STDDEV(vii_count) AS std_dev_vii,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY vii_count) AS p25_vii,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vii_count) AS p50_vii,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY vii_count) AS p75_vii,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY vii_count) AS p95_vii,
  AVG(hypotensive_count) AS avg_hypotensive,
  AVG(tachycardic_count) AS avg_tachycardic,
  AVG(los) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM other_group_vii;