WITH ugib_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (LOWER(d_icd.long_title) LIKE '%upper gastrointestinal bleeding%'
         OR LOWER(d_icd.long_title) LIKE '%upper gi bleed%'
         OR LOWER(d_icd.long_title) LIKE '%gastric hemorrhage%'
         OR LOWER(d_icd.long_title) LIKE '%esophageal hemorrhage%'
         OR LOWER(d_icd.long_title) LIKE '%duodenal hemorrhage%'
         OR LOWER(d_icd.long_title) LIKE '%upper gi hemorrhage%'
         OR LOWER(d_icd.long_title) LIKE '%gastrointestinal bleeding%'
         OR LOWER(d_icd.long_title) LIKE '%peptic ulcer hemorrhage%'
         OR LOWER(d_icd.long_title) LIKE '%variceal bleeding%'
         OR LOWER(d_icd.long_title) LIKE '%hematemesis%'
         OR LOWER(d_icd.long_title) LIKE '%melena%')
),

first_icu_stay AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los,
         ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN ugib_patients u ON i.subject_id = u.subject_id AND i.hadm_id = u.hadm_id
),

diagnostic_procedures AS (
  SELECT pe.stay_id, COUNT(*) AS proc_count_24h
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  JOIN first_icu_stay fis ON pe.stay_id = fis.stay_id
  WHERE fis.rn = 1
    AND (LOWER(di.label) LIKE '%endoscop%'
         OR LOWER(di.label) LIKE '%gastroscop%'
         OR LOWER(di.label) LIKE '%colonosc%'
         OR LOWER(di.label) LIKE '%esophagogastroduodenoscop%'
         OR LOWER(di.label) LIKE '%upper gi endoscop%'
         OR LOWER(di.label) LIKE '%duodenoscop%'
         OR LOWER(di.label) LIKE '%gastroenterolog%'
         OR LOWER(di.label) LIKE '%diagnostic endoscop%'
         OR LOWER(di.label) LIKE '%upper gi endoscopy%'
         OR LOWER(di.label) LIKE '%esophagogastroduodenoscopy%'
         OR LOWER(di.label) LIKE '%colonoscopy%'
         OR LOWER(di.label) LIKE '%gastroscopy%')
    AND pe.starttime >= fis.intime
    AND pe.starttime <= fis.intime + INTERVAL '24 hours'
  GROUP BY pe.stay_id
),

admission_info AS (
  SELECT a.hadm_id, a.hospital_expire_flag, 
         EXTRACT(EPOCH FROM (a.dischtime - a.admittime)) / 3600 / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN first_icu_stay fis ON a.hadm_id = fis.hadm_id
  WHERE fis.rn = 1
),

quintiles AS (
  SELECT 
    fis.stay_id,
    COALESCE(dp.proc_count_24h, 0) AS proc_count_24h,
    ai.los_days,
    ai.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY COALESCE(dp.proc_count_24h, 0)) AS quintile
  FROM first_icu_stay fis
  LEFT JOIN diagnostic_procedures dp ON fis.stay_id = dp.stay_id
  JOIN admission_info ai ON fis.hadm_id = ai.hadm_id
)

SELECT 
  quintile,
  AVG(proc_count_24h) AS avg_procedures,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct
FROM quintiles
GROUP BY quintile
ORDER BY quintile;