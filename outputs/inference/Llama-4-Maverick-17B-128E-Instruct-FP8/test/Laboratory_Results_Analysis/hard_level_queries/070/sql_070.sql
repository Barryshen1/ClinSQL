WITH target_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
  AND dicd.long_title LIKE '%Hemorrhagic stroke%'
),
lab_measurements AS (
  SELECT tp.subject_id, tp.hadm_id, COUNT(DISTINCT CASE WHEN le.valuenum < dli.ref_range_lower OR le.valuenum > dli.ref_range_upper THEN le.itemid END) AS lab_instability_score
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON tp.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE le.charttime BETWEEN tp.admittime AND TIMESTAMP_ADD(tp.admittime, INTERVAL 72 HOUR)
  AND dli.ref_range_lower IS NOT NULL AND dli.ref_range_upper IS NOT NULL  -- Ensure valid reference range
  GROUP BY tp.subject_id, tp.hadm_id
),
stratified_lab_scores AS (
  SELECT subject_id, hadm_id, lab_instability_score,
         NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM lab_measurements
),
patient_outcomes AS (
  SELECT tp.subject_id, tp.hadm_id,
         DATETIME_DIFF(tp.dischtime, tp.admittime, HOUR) AS los,
         CASE WHEN tp.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality
  FROM target_patients tp
)
SELECT 
  sls.quartile,
  AVG(po.los) AS avg_los,
  AVG(po.mortality) AS avg_mortality
FROM stratified_lab_scores sls
JOIN patient_outcomes po ON sls.hadm_id = po.hadm_id
GROUP BY sls.quartile
ORDER BY sls.quartile;