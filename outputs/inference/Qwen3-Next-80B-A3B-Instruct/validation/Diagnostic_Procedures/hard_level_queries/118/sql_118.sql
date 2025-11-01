WITH amifemale AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
),

first_icu_stay AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN amifemale af ON i.hadm_id = af.hadm_id
),

first_icu_procedures AS (
  SELECT
    f.stay_id,
    COUNT(*) AS procedure_count
  FROM first_icu_stay f
  INNER JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON f.stay_id = pe.stay_id
  WHERE pe.starttime >= f.intime
    AND pe.starttime <= DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
    AND pe.starttime IS NOT NULL
  GROUP BY f.stay_id
),

quartiles AS (
  SELECT
    af.subject_id,
    af.hadm_id,
    af.los_days,
    af.hospital_expire_flag,
    COALESCE(fp.procedure_count, 0) AS procedure_count,
    NTILE(4) OVER (ORDER BY COALESCE(fp.procedure_count, 0)) AS quartile
  FROM amifemale af
  LEFT JOIN first_icu_stay fis ON af.hadm_id = fis.hadm_id
  LEFT JOIN first_icu_procedures fp ON fis.stay_id = fp.stay_id
)

SELECT
  quartile,
  COUNT(*) AS n_per_quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(los_days) AS mean_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;