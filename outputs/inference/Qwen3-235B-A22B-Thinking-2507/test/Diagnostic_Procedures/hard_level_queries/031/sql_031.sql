WITH readmission_flag AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN next_admittime <= dischtime + INTERVAL '30' DAY THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM (
    SELECT 
      hadm_id,
      dischtime,
      LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  )
),
hhs_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('E1101', 'E0801', 'E0901', 'E1301') 
    AND icd_version = 10
),
icu_stays_filtered AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  INNER JOIN hhs_patients hhs
    ON icu.subject_id = hhs.subject_id AND icu.hadm_id = hhs.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 66 AND 76
),
procedure_counts AS (
  SELECT 
    icu.stay_id,
    COUNT(proc.stay_id) AS procedure_count
  FROM icu_stays_filtered icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` proc
    ON icu.stay_id = proc.stay_id
    AND proc.starttime >= icu.intime
    AND proc.starttime < icu.intime + INTERVAL '48' HOUR
  GROUP BY icu.stay_id
),
stays_with_info AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    pc.procedure_count,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los,
    COALESCE(rf.readmitted_30d, 0) AS readmitted_30d
  FROM icu_stays_filtered icu
  INNER JOIN procedure_counts pc
    ON icu.stay_id = pc.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  LEFT JOIN readmission_flag rf
    ON icu.hadm_id = rf.hadm_id
),
stays_with_quintile AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM stays_with_info
)
SELECT 
  quintile,
  COUNT(*) AS num_stays,
  AVG(procedure_count) AS mean_procedures,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_pct,
  AVG(hospital_los) AS mean_hospital_los,
  AVG(readmitted_30d) * 100 AS readmission_30d_pct
FROM stays_with_quintile
GROUP BY quintile
ORDER BY quintile;