WITH base_cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        ie.hadm_id = di.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '410%') 
          OR 
          (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
        )
    )
),
cohort_with_proc AS (
  SELECT 
    bc.*,
    COALESCE((
      SELECT COUNT(DISTINCT pe.itemid)
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE 
        pe.stay_id = bc.stay_id
        AND pe.starttime >= bc.intime
        AND pe.starttime < DATETIME_ADD(bc.intime, INTERVAL 24 HOUR)
    ), 0) AS distinct_procedure_count
  FROM base_cohort bc
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY distinct_procedure_count) AS quartile
  FROM cohort_with_proc
)
SELECT 
  quartile,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS hospital_mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;