WITH 
pe_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 65 AND 75 
    AND d_diag.long_title LIKE '%Pulmonary embolism%'
),
first_icu_stay AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM (
    SELECT subject_id, hadm_id, stay_id, intime, 
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS icu_stay_num
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE subject_id IN (SELECT subject_id FROM pe_patients)
  ) WHERE icu_stay_num = 1
),
proc_count AS (
  SELECT f.subject_id, COUNT(pe.itemid) AS proc_count
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON f.stay_id = pe.stay_id
  WHERE pe.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 72 HOUR)
  GROUP BY f.subject_id
),
icu_data AS (
  SELECT f.subject_id, 
         TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) / 24 AS icu_los,
         a.hospital_expire_flag
  FROM first_icu_stay f
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON f.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
),
combined_data AS (
  SELECT pc.proc_count, id.icu_los, id.hospital_expire_flag,
         NTILE(4) OVER (ORDER BY pc.proc_count) AS quartile
  FROM proc_count pc
  INNER JOIN icu_data id ON pc.subject_id = id.subject_id
),
quartile_data AS (
  SELECT quartile,
         COUNT(*) AS N,
         AVG(proc_count) AS mean_proc_count,
         AVG(icu_los) AS mean_icu_los,
         AVG(hospital_expire_flag) * 100 AS hospital_mortality_pct
  FROM combined_data
  GROUP BY quartile
)
SELECT quartile, N, mean_proc_count, mean_icu_los, hospital_mortality_pct
FROM quartile_data
ORDER BY quartile;