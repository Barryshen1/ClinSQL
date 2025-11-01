WITH dka_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    adm.admittime,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_code = 'E101' AND icd_version = 10) OR  -- ICD-10 DKA codes
        (icd_code = 'E111' AND icd_version = 10) OR
        (icd_code = 'E131' AND icd_version = 10) OR
        (icd_code = 'E141' AND icd_version = 10)
    )
),
filtered_admissions AS (
  SELECT *
  FROM dka_admissions
  WHERE age_adm BETWEEN 39 AND 49
),
first_icu_stay AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN filtered_admissions adm
    ON icu.hadm_id = adm.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) = 1
),
procedure_counts AS (
  SELECT 
    icu.stay_id,
    COUNT(DISTINCT pe.itemid) AS proc_count
  FROM first_icu_stay icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON icu.stay_id = pe.stay_id
    AND pe.starttime >= icu.intime
    AND pe.starttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY icu.stay_id
),
base_data AS (
  SELECT 
    icu.stay_id,
    icu.los,
    adm.hospital_expire_flag,
    COALESCE(pc.proc_count, 0) AS proc_count
  FROM first_icu_stay icu
  INNER JOIN filtered_admissions adm
    ON icu.hadm_id = adm.hadm_id
  LEFT JOIN procedure_counts pc
    ON icu.stay_id = pc.stay_id
),
quintiles AS (
  SELECT 
    stay_id,
    proc_count,
    los,
    hospital_expire_flag,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM base_data
)
SELECT 
  quintile,
  COUNT(stay_id) AS num_stays,
  AVG(proc_count) AS mean_proc_count,
  MIN(proc_count) AS min_proc_count,
  MAX(proc_count) AS max_proc_count,
  AVG(los) AS mean_icu_los,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS hospital_mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;