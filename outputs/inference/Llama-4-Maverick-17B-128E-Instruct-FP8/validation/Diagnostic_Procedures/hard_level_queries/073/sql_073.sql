WITH 
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
),
first_icu_stay AS (
  SELECT subject_id, hadm_id, stay_id, intime,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) as icu_stay_num
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE subject_id IN (SELECT subject_id FROM eligible_patients)
),
hepatic_failure_patients AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Hepatic failure%' 
  AND d.subject_id IN (SELECT subject_id FROM first_icu_stay WHERE icu_stay_num = 1)
),
diagnostic_procedures AS (
  SELECT fis.stay_id, COUNT(DISTINCT pe.itemid) as num_procedures
  FROM first_icu_stay fis
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON fis.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE pe.starttime <= fis.intime + INTERVAL 3 DAY AND di.category = 'Diagnostic'
  AND fis.icu_stay_num = 1 AND fis.subject_id IN (SELECT subject_id FROM hepatic_failure_patients)
  GROUP BY fis.stay_id
),
quartiles AS (
  SELECT num_procedures, 
         NTILE(4) OVER (ORDER BY num_procedures) as quartile
  FROM diagnostic_procedures
),
stats AS (
  SELECT 
    q.quartile,
    COUNT(*) as num_patients,
    MIN(q.num_procedures) as min_procedures,
    MAX(q.num_procedures) as max_procedures,
    AVG(q.num_procedures) as mean_procedures,
    AVG(i.los) as mean_los,
    AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 as mortality_percent
  FROM quartiles q
  JOIN diagnostic_procedures dp ON q.num_procedures = dp.num_procedures
  JOIN first_icu_stay fis ON dp.stay_id = fis.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON fis.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fis.hadm_id = a.hadm_id
  WHERE fis.icu_stay_num = 1
  GROUP BY q.quartile
)

SELECT * FROM stats ORDER BY quartile;