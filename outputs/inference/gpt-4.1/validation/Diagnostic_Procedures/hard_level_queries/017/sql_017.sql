WITH cohort AS (
  -- Select male patients aged 83-93 with first ICU stay and sepsis diagnosis
  SELECT
    p.subject_id,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
      ON p.subject_id = i.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
      ON i.hadm_id = a.hadm_id
    INNER JOIN (
      -- Sepsis ICD codes (ICD-9 and ICD-10)
      SELECT DISTINCT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
      WHERE
        (
          (icd_version = 9 AND (
            icd_code LIKE '99591' OR
            icd_code LIKE '99592' OR
            icd_code LIKE '78552'
          )) OR
          (icd_version = 10 AND (
            icd_code LIKE 'A40%' OR
            icd_code LIKE 'A41%'
          ))
        )
    ) sepsis
      ON i.hadm_id = sepsis.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
first_icu AS (
  -- Only first ICU stay per patient
  SELECT *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM cohort
  )
  WHERE rn = 1
),
proc_72h AS (
  -- Procedures within first 72h of ICU stay
  SELECT
    f.subject_id,
    f.stay_id,
    COUNT(DISTINCT p.icd_code) AS procedure_count
  FROM first_icu f
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd p
    ON f.subject_id = p.subject_id
    AND f.hadm_id = p.hadm_id
    AND p.chartdate >= DATE(f.intime)
    AND p.chartdate < DATE_ADD(DATE(f.intime), INTERVAL 3 DAY)
  GROUP BY f.subject_id, f.stay_id
),
final AS (
  -- Merge procedure counts with cohort
  SELECT
    f.subject_id,
    f.stay_id,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    f.los,
    f.hospital_expire_flag
  FROM first_icu f
  LEFT JOIN proc_72h p
    ON f.subject_id = p.subject_id
    AND f.stay_id = p.stay_id
),
quartiles AS (
  -- Assign quartile based on procedure_count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS proc_quartile
  FROM final
)
SELECT
  proc_quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(los),2) AS mean_icu_los_days,
  ROUND(100.0 * AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END),2) AS mortality_percent
FROM quartiles
GROUP BY proc_quartile
ORDER BY proc_quartile;