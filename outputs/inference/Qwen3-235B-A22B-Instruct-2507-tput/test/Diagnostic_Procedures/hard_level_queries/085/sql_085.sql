WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    DATETIME_ADD(a.admittime, INTERVAL 48 HOUR) AS admittime_plus_48h
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 87 AND 97
),

icu_stays_with_diagnosis AS (
  SELECT
    pa.*,
    icd.icd_code,
    icd.icd_version,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY i.intime) AS stay_rank
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pa.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd
    ON pa.hadm_id = icd.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON icd.icd_code = d.icd_code AND icd.icd_version = d.icd_version
  WHERE d.long_title LIKE '%lower gastrointestinal bleed%'
     OR d.long_title LIKE '%lower GI bleed%'
     OR (icd.icd_code = 'K922' AND icd.icd_version = 10)
),

first_icu_stay AS (
  SELECT *
  FROM icu_stays_with_diagnosis
  WHERE stay_rank = 1
),

procedures_in_48h AS (
  SELECT
    f.stay_id,
    COUNT(DISTINCT p.itemid) AS distinct_procedure_count
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.stay_id = p.stay_id
    AND p.starttime >= f.intime
    AND p.starttime <= DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY f.stay_id
),

quintiles AS (
  SELECT
    f.*,
    COALESCE(p.distinct_procedure_count, 0) AS proc_count,
    NTILE(5) OVER (ORDER BY COALESCE(p.distinct_procedure_count, 0)) AS quintile
  FROM first_icu_stay f
  LEFT JOIN procedures_in_48h p ON f.stay_id = p.stay_id
)

SELECT
  quintile,
  AVG(proc_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(CAST(hospital_expire_flag AS INT64)) * 100 AS in_hospital_mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;