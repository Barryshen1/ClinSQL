WITH patients_acs AS (
  SELECT p.subject_id, p.anchor_age, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 53 AND 63
  AND dicd.long_title LIKE '%Acute coronary syndrome%'
),
lab_events AS (
  SELECT le.hadm_id, COUNT(DISTINCT dl.category) as lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON le.hadm_id = a.hadm_id
  WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  AND (le.flag = 'abnormal' OR le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY le.hadm_id
),
combined_data AS (
  SELECT pa.hadm_id, COALESCE(le.lab_instability_score, 0) as lab_instability_score,
         a.deathtime IS NOT NULL AS mortality,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los
  FROM patients_acs pa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON pa.hadm_id = a.hadm_id
  LEFT JOIN lab_events le ON pa.hadm_id = le.hadm_id
),
quartiles AS (
  SELECT hadm_id, lab_instability_score,
         NTILE(4) OVER (ORDER BY lab_instability_score) as quartile
  FROM combined_data
),
outcome_analysis AS (
  SELECT q.quartile,
         AVG(CAST(cd.mortality AS INT64)) * 100 AS mortality_percent,
         AVG(cd.los) AS avg_los
  FROM quartiles q
  JOIN combined_data cd ON q.hadm_id = cd.hadm_id
  GROUP BY q.quartile
)
SELECT * FROM outcome_analysis
ORDER BY quartile;