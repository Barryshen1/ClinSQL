WITH hf_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
  AND dicd.long_title LIKE '%Heart failure%'
),
icu_los AS (
  SELECT hadm_id, SUM(LOS) AS total_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
mri_ct_scans AS (
  SELECT h.hadm_id, COUNT(*) AS num_scans
  FROM hf_patients h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc ON h.hadm_id = hc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON hc.hcpcs_cd = dh.code
  WHERE dh.short_description LIKE '%CT%' OR dh.short_description LIKE '%MRI%'
  GROUP BY h.hadm_id
),
diagnosis_type AS (
  SELECT d.hadm_id, 
         CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type
  FROM hf_patients h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON h.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Heart failure%'
)

SELECT 
  CASE 
    WHEN il.total_los BETWEEN 1 AND 3 THEN '1-3'
    WHEN il.total_los BETWEEN 4 AND 7 THEN '4-7'
    ELSE 'Other'
  END AS los_category,
  dt.diagnosis_type,
  COUNT(DISTINCT h.hadm_id) AS admission_count,
  AVG(mcs.num_scans) AS mean_mri_ct
FROM hf_patients h
LEFT JOIN icu_los il ON h.hadm_id = il.hadm_id
LEFT JOIN mri_ct_scans mcs ON h.hadm_id = mcs.hadm_id
LEFT JOIN diagnosis_type dt ON h.hadm_id = dt.hadm_id
WHERE il.total_los BETWEEN 1 AND 7
GROUP BY los_category, dt.diagnosis_type
ORDER BY los_category, dt.diagnosis_type;