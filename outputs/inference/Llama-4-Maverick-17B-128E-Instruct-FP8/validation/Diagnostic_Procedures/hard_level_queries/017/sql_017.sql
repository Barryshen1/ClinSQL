WITH 
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 83 AND 93
),
sepsis_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.long_title LIKE '%Sepsis%' OR d.long_title LIKE '%septic%')
),
first_icu_stay AS (
  SELECT subject_id, hadm_id, stay_id, intime, outtime, 
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS icu_stay_num
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
sepsis_first_icu AS (
  SELECT ep.subject_id, fis.hadm_id, fis.stay_id, fis.intime
  FROM eligible_patients ep
  JOIN sepsis_patients sp ON ep.subject_id = sp.subject_id
  JOIN first_icu_stay fis ON sp.subject_id = fis.subject_id AND sp.hadm_id = fis.hadm_id
  WHERE fis.icu_stay_num = 1
),
diagnostic_intensity AS (
  SELECT sf.stay_id, COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM sepsis_first_icu sf
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON sf.stay_id = pe.stay_id
  WHERE pe.starttime <= sf.intime + INTERVAL 3 DAY
  GROUP BY sf.stay_id
),
quartiles AS (
  SELECT stay_id, num_procedures,
         NTILE(4) OVER (ORDER BY num_procedures) AS quartile
  FROM diagnostic_intensity
),
icu_los_mortality AS (
  SELECT fis.stay_id, fis.intime, fis.outtime, 
         (DATE_DIFF(fis.outtime, fis.intime, DAY)) AS icu_los_days,
         a.hospital_expire_flag AS mortality_flag
  FROM first_icu_stay fis
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fis.hadm_id = a.hadm_id
),
final_data AS (
  SELECT q.quartile, q.num_procedures, ilm.icu_los_days, ilm.mortality_flag
  FROM quartiles q
  JOIN icu_los_mortality ilm ON q.stay_id = ilm.stay_id
)
SELECT 
  quartile,
  AVG(num_procedures) AS mean_procedure_count,
  AVG(icu_los_days) AS mean_icu_los_days,
  AVG(mortality_flag) * 100 AS mortality_percentage
FROM final_data
GROUP BY quartile
ORDER BY quartile;