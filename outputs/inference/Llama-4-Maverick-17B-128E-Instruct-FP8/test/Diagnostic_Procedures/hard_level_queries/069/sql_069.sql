WITH 
pe_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
  ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Pulmonary embolism%' AND d.icd_version = 10
),
filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 44 AND 54
  AND a.hadm_id IN (SELECT hadm_id FROM pe_patients)
  AND icu.stay_id IN (SELECT stay_id FROM (
    SELECT stay_id, ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) as rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) WHERE rn = 1)
),
procedure_counts AS (
  SELECT fp.subject_id, fp.hadm_id, COUNT(DISTINCT pe.itemid) as procedure_count
  FROM filtered_patients fp
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON fp.stay_id = pe.stay_id
  WHERE pe.starttime BETWEEN fp.intime AND TIMESTAMP_ADD(fp.intime, INTERVAL 72 HOUR)
  GROUP BY fp.subject_id, fp.hadm_id
),
patient_outcomes AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS hospital_los,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
combined_data AS (
  SELECT pc.procedure_count, po.hospital_los, po.hospital_expire_flag,
         NTILE(5) OVER (ORDER BY pc.procedure_count) as quintile
  FROM procedure_counts pc
  JOIN patient_outcomes po ON pc.hadm_id = po.hadm_id
),
quintile_averages AS (
  SELECT quintile,
         AVG(procedure_count) as avg_procedure_count,
         AVG(hospital_los) as avg_hospital_los,
         AVG(hospital_expire_flag) * 100 as mortality_percent
  FROM combined_data
  GROUP BY quintile
)
SELECT quintile,
       avg_procedure_count,
       avg_hospital_los,
       mortality_percent
FROM quintile_averages
ORDER BY quintile;