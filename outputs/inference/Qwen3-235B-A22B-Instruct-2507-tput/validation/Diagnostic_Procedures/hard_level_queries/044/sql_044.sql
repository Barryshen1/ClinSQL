WITH eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),
admissions_with_shock AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code = 'R57.0' AND d.icd_version = 10
),
first_icu_stay AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  INNER JOIN eligible_patients ep ON ie.subject_id = ep.subject_id
  WHERE ie.hadm_id IN (SELECT hadm_id FROM admissions_with_shock)
),
first_stay AS (
  SELECT *
  FROM first_icu_stay
  WHERE rn = 1
),
procedure_counts AS (
  SELECT 
    fs.stay_id,
    fs.hadm_id,
    COUNT(pe.itemid) AS procedure_count_24h
  FROM first_stay fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON fs.stay_id = pe.stay_id
    AND pe.starttime >= fs.intime
    AND pe.starttime < DATETIME_ADD(fs.intime, INTERVAL 24 HOUR)
  GROUP BY fs.stay_id, fs.hadm_id
),
quintiles AS (
  SELECT 
    pc.stay_id,
    pc.hadm_id,
    pc.procedure_count_24h,
    NTILE(5) OVER (ORDER BY pc.procedure_count_24h) AS quintile
  FROM procedure_counts pc
)
SELECT
  q.quintile,
  AVG(q.procedure_count_24h) AS mean_procedure_count,
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS mean_hospital_los_days,
  AVG(a.hospital_expire_flag) * 100 AS in_hospital_mortality_percentage
FROM quintiles q
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON q.hadm_id = a.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;