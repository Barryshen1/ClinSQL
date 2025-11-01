WITH 
filtered_patients AS (
  SELECT p.subject_id, p.gender, a.hadm_id, a.admittime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 39 AND 49
),
dka_patients AS (
  SELECT DISTINCT a.hadm_id
  FROM filtered_patients a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Diabetic ketoacidosis%' OR di.icd_code IN ('E10.1', 'E11.1', 'E13.1')  
),
first_icu_stay AS (
  SELECT subject_id, hadm_id, stay_id, intime, outtime, los,
         ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS icu_stay_num
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
procedure_counts AS (
  SELECT fis.hadm_id, COUNT(DISTINCT pe.itemid) AS procedure_count, fis.los, fp.hospital_expire_flag
  FROM first_icu_stay fis
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON fis.stay_id = pe.stay_id
  JOIN filtered_patients fp ON fis.hadm_id = fp.hadm_id
  JOIN dka_patients dka ON fis.hadm_id = dka.hadm_id
  WHERE fis.icu_stay_num = 1 AND pe.starttime <= fis.intime + INTERVAL 1 DAY
  GROUP BY fis.hadm_id, fis.los, fp.hospital_expire_flag
),
quintiles AS (
  SELECT hadm_id, procedure_count, los, hospital_expire_flag,
         NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM procedure_counts
),
stats AS (
  SELECT q.quintile,
         COUNT(q.hadm_id) AS num_stays,
         AVG(q.procedure_count) AS mean_procedure_count,
         MIN(q.procedure_count) AS min_procedure_count,
         MAX(q.procedure_count) AS max_procedure_count,
         AVG(q.los) AS mean_icu_los,
         AVG(CASE WHEN q.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS hospital_mortality_pct
  FROM quintiles q
  GROUP BY q.quintile
)
SELECT * FROM stats
ORDER BY quintile;