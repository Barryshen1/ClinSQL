WITH sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (icd_version = 10 AND icd_code LIKE 'A41%' OR icd_code IN ('R6520', 'R6521'))
  )
),
patients_sepsis AS (
  SELECT DISTINCT adm.hadm_id, adm.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN sepsis_codes s
    ON diag.icd_code = s.icd_code AND diag.icd_version = 10
),
first_icu_stay AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN patients_sepsis ps ON icu.hadm_id = ps.hadm_id
),
eligible_patients AS (
  SELECT 
    fis.*
  FROM first_icu_stay fis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fis.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND fis.rn = 1
),
procedure_counts AS (
  SELECT 
    ep.stay_id,
    COUNT(DISTINCT ep.itemid) AS distinct_procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` ep
  INNER JOIN eligible_patients epat ON ep.stay_id = epat.stay_id
  WHERE ep.starttime <= DATETIME_ADD(epat.intime, INTERVAL 72 HOUR)
    AND ep.starttime >= epat.intime
  GROUP BY ep.stay_id
),
quartiles AS (
  SELECT 
    epat.stay_id,
    COALESCE(pc.distinct_procedure_count, 0) AS proc_count,
    NTILE(4) OVER (ORDER BY COALESCE(pc.distinct_procedure_count, 0)) AS quartile,
    epat.los,
    adm.hospital_expire_flag
  FROM eligible_patients epat
  LEFT JOIN procedure_counts pc ON epat.stay_id = pc.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON epat.hadm_id = adm.hadm_id
)
SELECT
  quartile,
  AVG(proc_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;