WITH 
patients_filtered AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53
),
hepatic_failure AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Hepatic failure%' OR dicd.long_title LIKE '%Liver failure%'
),
med_complexity AS (
  SELECT pf.hadm_id, COUNT(DISTINCT pr.drug) AS med_count
  FROM patients_filtered pf
  JOIN hepatic_failure hf ON pf.hadm_id = hf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pf.hadm_id = pr.hadm_id
  WHERE pr.starttime BETWEEN pf.admittime AND TIMESTAMP_ADD(pf.admittime, INTERVAL 72 HOUR)
  GROUP BY pf.hadm_id
),
patient_outcomes AS (
  SELECT pf.hadm_id, 
         TIMESTAMP_DIFF(pf.dischtime, pf.admittime, HOUR) / 24 AS los,
         CASE WHEN pf.deathtime IS NOT NULL THEN 1 ELSE 0 END AS in_hospital_mortality,
         LEAD(pf.admittime, 1) OVER (PARTITION BY pf.subject_id ORDER BY pf.admittime) AS next_admit,
         pf.dischtime
  FROM patients_filtered pf
  JOIN hepatic_failure hf ON pf.hadm_id = hf.hadm_id
),
combined_data AS (
  SELECT mc.hadm_id, mc.med_count, po.los, po.in_hospital_mortality,
         CASE WHEN TIMESTAMP_DIFF(po.next_admit, po.dischtime, DAY) <= 30 THEN 1 ELSE 0 END AS readmit_30day
  FROM med_complexity mc
  JOIN patient_outcomes po ON mc.hadm_id = po.hadm_id
),
quintiles AS (
  SELECT hadm_id, med_count, los, in_hospital_mortality, readmit_30day,
         NTILE(5) OVER (ORDER BY med_count) AS quintile
  FROM combined_data
)
SELECT 
  quintile,
  COUNT(*) AS n,
  MIN(med_count) AS min_med_count,
  MAX(med_count) AS max_med_count,
  AVG(med_count) AS mean_med_count,
  AVG(los) AS mean_los,
  AVG(in_hospital_mortality) * 100 AS in_hospital_mortality_pct,
  AVG(readmit_30day) * 100 AS readmit_30day_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;