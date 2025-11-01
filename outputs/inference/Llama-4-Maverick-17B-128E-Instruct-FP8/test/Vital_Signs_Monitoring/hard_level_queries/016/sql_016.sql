WITH 
patients_filtered AS (
  SELECT p.subject_id, p.anchor_age, 
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
           JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
           ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
           WHERE d.subject_id = p.subject_id AND dicd.long_title LIKE '%Transplant%'
         ) OR EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
           JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di
           ON pr.icd_code = di.icd_code AND pr.icd_version = di.icd_version
           WHERE pr.subject_id = p.subject_id AND di.long_title LIKE '%Transplant%'
         ) THEN 'Transplant' ELSE 'Non-Transplant' END AS transplant_status
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 57 AND 67
),
icustays_filtered AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, 
         TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_filtered p ON i.subject_id = p.subject_id
),
instability_score AS (
  SELECT i.stay_id, 
         SUM(CASE WHEN c.itemid = 223762 AND c.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_count,
         SUM(CASE WHEN c.itemid = 220277 AND c.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_count,
         SUM(CASE WHEN c.itemid = 220210 AND c.valuenum > 20 THEN 1 ELSE 0 END) AS rr_count
  FROM icustays_filtered i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  AND c.itemid IN (223762, 220277, 220210)
  GROUP BY i.stay_id
),
outcomes AS (
  SELECT pf.transplant_status, 
         i.stay_id,
         (COALESCE(is.fever_count, 0) + COALESCE(is.spo2_count, 0) + COALESCE(is.rr_count, 0)) AS composite_instability_score,
         i.icu_los_hours,
         CAST(a.deathtime IS NOT NULL AS INT64) AS mortality
  FROM patients_filtered pf
  JOIN icustays_filtered i ON pf.subject_id = i.subject_id
  LEFT JOIN instability_score is ON i.stay_id = is.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)
SELECT transplant_status,
       APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(50)] AS median_composite_instability_score,
       APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(50)] AS median_icu_los_hours,
       AVG(mortality) AS mortality_rate
FROM outcomes
GROUP BY transplant_status;