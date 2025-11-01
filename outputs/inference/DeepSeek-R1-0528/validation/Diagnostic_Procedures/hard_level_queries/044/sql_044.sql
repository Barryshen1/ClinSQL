WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ie.stay_id,
    ie.intime AS icu_intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON a.hadm_id = ie.hadm_id
    AND p.subject_id = ie.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.subject_id = a.subject_id
        AND diag.hadm_id = a.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code = '78551') 
          OR (diag.icd_version = 10 AND diag.icd_code = 'R570')
        )
    )
),

procedures AS (
  SELECT 
    c.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.icu_intime
    AND pe.starttime < DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),

final_data AS (
  SELECT 
    c.*,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS hospital_los_days
  FROM cohort c
  LEFT JOIN procedures p
    ON c.stay_id = p.stay_id
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM final_data
)

SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los_days) AS mean_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_percentage
FROM quintiles
GROUP BY quintile
ORDER BY quintile;