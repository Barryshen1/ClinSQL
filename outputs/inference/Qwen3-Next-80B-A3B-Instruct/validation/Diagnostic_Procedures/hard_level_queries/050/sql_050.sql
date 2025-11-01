WITH amicu_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND (
      d.icd_code LIKE 'I21%'   -- ICD-10 AMI codes
      OR d.icd_code LIKE 'I22%'
      OR d.icd_code LIKE 'I23%'
      OR d.icd_code LIKE '410%' -- ICD-9 AMI codes
    )
),
proc_count_24h AS (
  SELECT
    ac.stay_id,
    COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
  FROM amicu_patients ac
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON ac.stay_id = pe.stay_id
  WHERE pe.starttime >= ac.intime
    AND pe.starttime < ac.intime + INTERVAL '24' HOUR
  GROUP BY ac.stay_id
),
quartiles AS (
  SELECT
    ac.subject_id,
    ac.stay_id,
    ac.los,
    ac.hospital_expire_flag,
    COALESCE(pc.distinct_procedure_count, 0) AS distinct_procedure_count,
    NTILE(4) OVER (ORDER BY COALESCE(pc.distinct_procedure_count, 0)) AS procedure_quartile
  FROM amicu_patients ac
  LEFT JOIN proc_count_24h pc
    ON ac.stay_id = pc.stay_id
)
SELECT
  procedure_quartile,
  AVG(distinct_procedure_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_percent
FROM quartiles
GROUP BY procedure_quartile
ORDER BY procedure_quartile;