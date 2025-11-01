WITH patients_filtered AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + TIMESTAMP_DIFF(a.admittime, TIMESTAMP(DATE(p.anchor_year, 1, 1)), YEAR) BETWEEN 87 AND 97
),
patients_with_diagnosis AS (
  SELECT 
    pf.subject_id,
    pf.hadm_id,
    pf.admittime,
    pf.anchor_age,
    pf.anchor_year,
    pf.hospital_expire_flag
  FROM patients_filtered pf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON pf.hadm_id = d.hadm_id
  WHERE d.icd_version = 10
    AND d.icd_code IN (
      'K570', 'K571', 'K573', 'K574', 'K575', 'K578', 'K579', 
      'K625', 'K635', 'K640', 'K641', 'K642', 'K643', 'K644', 'K648', 'K649'
    )
  GROUP BY pf.subject_id, pf.hadm_id, pf.admittime, pf.anchor_age, pf.anchor_year, pf.hospital_expire_flag
),
first_icu_stay AS (
  SELECT 
    pwd.subject_id,
    pwd.hadm_id,
    pwd.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM patients_with_diagnosis pwd
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON pwd.hadm_id = i.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pwd.subject_id ORDER BY i.intime) = 1
),
procedure_counts AS (
  SELECT 
    f.stay_id,
    f.hadm_id,
    f.subject_id,
    f.hospital_expire_flag,
    f.los,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents p
    ON f.stay_id = p.stay_id
    AND p.starttime >= f.intime
    AND p.starttime <= TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY f.stay_id, f.hadm_id, f.subject_id, f.hospital_expire_flag, f.los
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM procedure_counts
)
SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;