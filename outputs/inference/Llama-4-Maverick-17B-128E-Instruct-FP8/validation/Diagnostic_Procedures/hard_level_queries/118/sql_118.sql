WITH ami_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  USING (icd_code, icd_version)
  WHERE long_title LIKE '%Acute myocardial infarction%'  
),
female_ami_44_54 AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  JOIN ami_patients ON a.hadm_id = ami_patients.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 44 AND 54
  AND icu.intime = (SELECT MIN(intime) FROM `physionet-data.mimiciv_3_1_icu`.icustays WHERE hadm_id = a.hadm_id)
),
procedure_counts AS (
  SELECT fa.subject_id, fa.hadm_id, COUNT(pe.itemid) as procedure_count
  FROM female_ami_44_54 fa
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  ON fa.stay_id = pe.stay_id AND pe.starttime BETWEEN fa.intime AND TIMESTAMP_ADD(fa.intime, INTERVAL 72 HOUR)
  GROUP BY fa.subject_id, fa.hadm_id
),
hospital_los_mortality AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN female_ami_44_54 fa ON a.hadm_id = fa.hadm_id
),
quartiles AS (
  SELECT procedure_count,
         NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM procedure_counts
),
summary_stats AS (
  SELECT q.quartile,
         COUNT(*) as n,
         AVG(pc.procedure_count) as mean_procedure_count,
         AVG(hlm.hospital_los) as mean_hospital_los,
         AVG(hlm.hospital_expire_flag) * 100 as in_hospital_mortality_pct
  FROM quartiles q
  JOIN procedure_counts pc ON q.procedure_count = pc.procedure_count
  JOIN hospital_los_mortality hlm ON pc.hadm_id = hlm.hadm_id
  GROUP BY q.quartile
)
SELECT * FROM summary_stats
ORDER BY quartile;