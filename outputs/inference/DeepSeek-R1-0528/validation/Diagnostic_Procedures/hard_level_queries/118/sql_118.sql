WITH patient_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND icd_code LIKE '410%') OR
      (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  ) diag 
    ON a.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
),
first_icu_stay AS (
  SELECT 
    pa.*,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pa.hadm_id = icu.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY icu.intime) = 1
),
procedure_counts AS (
  SELECT 
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    fis.admittime,
    fis.dischtime,
    fis.hospital_expire_flag,
    COUNT(pe.itemid) AS procedure_count
  FROM first_icu_stay fis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON fis.stay_id = pe.stay_id
    AND pe.starttime >= fis.intime
    AND pe.starttime < DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
  GROUP BY 
    fis.subject_id, fis.hadm_id, fis.stay_id, 
    fis.admittime, fis.dischtime, fis.hospital_expire_flag
),
with_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM procedure_counts
)
SELECT 
  quartile,
  COUNT(*) AS n,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS mean_hospital_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent
FROM with_quartiles
GROUP BY quartile
ORDER BY quartile;