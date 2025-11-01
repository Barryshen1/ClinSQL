WITH patients_ugib AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON p.subject_id = diag.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 60 AND 70
  AND d_diag.long_title LIKE '%Gastrointestinal hemorrhage%'  -- Simplification for UGIB
),
icu_stays AS (
  SELECT i.subject_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patients_ugib pugib ON i.subject_id = pugib.subject_id
),
vital_signs AS (
  SELECT icu.subject_id, icu.stay_id,
         MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum END) AS max_hr,
         MIN(CASE WHEN di.label = 'Mean Blood Pressure' THEN ce.valuenum END) AS min_map,
         MAX(CASE WHEN di.label = 'Respiratory Rate' THEN ce.valuenum END) AS max_rr
  FROM icu_stays icu
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  AND di.label IN ('Heart Rate', 'Mean Blood Pressure', 'Respiratory Rate')
  GROUP BY icu.subject_id, icu.stay_id
),
vital_instability AS (
  SELECT subject_id, stay_id,
         CASE WHEN max_hr > 100 THEN 1 ELSE 0 END + 
         CASE WHEN min_map < 65 THEN 1 ELSE 0 END + 
         CASE WHEN max_rr > 20 THEN 1 ELSE 0 END AS vital_instability_index
  FROM vital_signs
),
percentiles AS (
  SELECT APPROX_QUANTILES(vital_instability_index, 100)[OFFSET(95)] AS percentile_95
  FROM vital_instability
),
top_decile AS (
  SELECT subject_id, stay_id
  FROM vital_instability
  WHERE vital_instability_index >= (SELECT percentile_95 FROM percentiles)
),
outcomes AS (
  SELECT 
    vi.subject_id, vi.stay_id,
    vi.vital_instability_index,
    CASE WHEN vi.vital_instability_index >= (SELECT percentile_95 FROM percentiles) THEN 1 ELSE 0 END AS top_decile,
    icu.los,
    CASE WHEN icu.outtime >= p.dod THEN 1 ELSE 0 END AS mortality
  FROM vital_instability vi
  INNER JOIN icu_stays icus ON vi.stay_id = icus.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON vi.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icus.subject_id = p.subject_id
)
SELECT 
  AVG(CASE WHEN top_decile = 1 THEN vital_instability_index END) AS avg_vital_instability_top_decile,
  AVG(CASE WHEN top_decile = 0 THEN vital_instability_index END) AS avg_vital_instability_controls,
  AVG(CASE WHEN top_decile = 1 THEN los END) AS avg_los_top_decile,
  AVG(CASE WHEN top_decile = 0 THEN los END) AS avg_los_controls,
  SUM(CASE WHEN top_decile = 1 AND mortality = 1 THEN 1 ELSE 0 END) / SUM(CASE WHEN top_decile = 1 THEN 1 ELSE 0 END) AS mortality_top_decile,
  SUM(CASE WHEN top_decile = 0 AND mortality = 1 THEN 1 ELSE 0 END) / SUM(CASE WHEN top_decile = 0 THEN 1 ELSE 0 END) AS mortality_controls
FROM outcomes;