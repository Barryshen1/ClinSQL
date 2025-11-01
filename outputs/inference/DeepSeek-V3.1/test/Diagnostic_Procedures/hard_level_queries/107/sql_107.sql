WITH cohort AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.intime,
    p.outtime,
    p.los,
    a.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM (
    SELECT 
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.outtime,
      icu.los,
      ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS stay_seq
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  ) p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON p.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON p.stay_id = pe.stay_id
      AND pe.starttime >= p.intime
      AND pe.starttime <= DATETIME_ADD(p.intime, INTERVAL 72 HOUR)
  WHERE 
    pt.gender = 'F'
    AND pt.anchor_age BETWEEN 65 AND 75
    AND diag.icd_code LIKE 'I26%'
    AND p.stay_seq = 1
  GROUP BY 
    p.subject_id, p.hadm_id, p.stay_id, p.intime, p.outtime, p.los, a.hospital_expire_flag
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM cohort
)
SELECT 
  quartile,
  COUNT(*) AS N,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS hospital_mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;