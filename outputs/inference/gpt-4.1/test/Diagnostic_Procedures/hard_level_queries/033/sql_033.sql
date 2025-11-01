WITH pneumonia_patients AS (
  -- Identify patients with pneumonia diagnosis (ICD-9 480-486, ICD-10 J12-J18)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS INT64) BETWEEN 480 AND 486)
      OR
      (d.icd_version = 10 AND (
        dd.icd_code LIKE 'J12%' OR dd.icd_code LIKE 'J13%' OR dd.icd_code LIKE 'J14%' OR
        dd.icd_code LIKE 'J15%' OR dd.icd_code LIKE 'J16%' OR dd.icd_code LIKE 'J17%' OR
        dd.icd_code LIKE 'J18%'
      ))
    )
),
first_icu_stays AS (
  -- Get first ICU stay per patient
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
),
cohort AS (
  -- Filter to male, age 37-47, first ICU stay, with pneumonia
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los
  FROM first_icu_stays f
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON f.subject_id = p.subject_id
  INNER JOIN pneumonia_patients pn
    ON f.subject_id = pn.subject_id AND f.hadm_id = pn.hadm_id
  WHERE
    f.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
procedures_in_48h AS (
  -- Count distinct procedures in first 48h of ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT pr.icd_code) AS procedure_count
  FROM cohort c
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON c.subject_id = pr.subject_id
    AND c.hadm_id = pr.hadm_id
    AND pr.chartdate >= c.intime
    AND pr.chartdate < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
cohort_with_procedure_count AS (
  -- Add procedure count to cohort, fill 0 if none
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    IFNULL(p48.procedure_count, 0) AS procedure_count
  FROM cohort c
  LEFT JOIN procedures_in_48h p48
    ON c.subject_id = p48.subject_id AND c.hadm_id = p48.hadm_id AND c.stay_id = p48.stay_id
),
cohort_with_mortality AS (
  -- Add hospital mortality
  SELECT
    cp.subject_id,
    cp.hadm_id,
    cp.stay_id,
    cp.los,
    cp.procedure_count,
    a.hospital_expire_flag
  FROM cohort_with_procedure_count cp
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON cp.subject_id = a.subject_id AND cp.hadm_id = a.hadm_id
),
quintiled AS (
  -- Assign quintiles by procedure count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS procedure_count_quintile
  FROM cohort_with_mortality
)
SELECT
  procedure_count_quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(los),2) AS mean_icu_los_days,
  ROUND(AVG(hospital_expire_flag),4) AS hospital_mortality_rate
FROM quintiled
GROUP BY procedure_count_quintile
ORDER BY procedure_count_quintile;