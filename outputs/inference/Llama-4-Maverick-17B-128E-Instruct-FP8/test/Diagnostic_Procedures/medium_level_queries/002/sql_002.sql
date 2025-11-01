WITH tia_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE (diag.long_title LIKE '%Transient ischemic attack%' AND d.icd_version = 9)
  OR (diag.long_title LIKE '%Transient ischemic attack%' AND d.icd_version = 10)
),
patient_info AS (
  SELECT 
    a.hadm_id,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM tia_patients)
),
echo_count AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS echo_num
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE d.short_description LIKE '%Echocardiogram%' 
  GROUP BY h.hadm_id
)
SELECT 
  CASE 
    WHEN pi.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN pi.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Outside LOS range'
  END AS los_category,
  pi.icu_use,
  AVG(ec.echo_num) AS mean_echo_per_admission
FROM patient_info pi
LEFT JOIN echo_count ec ON pi.hadm_id = ec.hadm_id
WHERE pi.age BETWEEN 64 AND 74
  AND pi.gender = 'M'
  AND pi.los BETWEEN 1 AND 7
GROUP BY los_category, pi.icu_use
ORDER BY los_category, pi.icu_use;