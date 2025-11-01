WITH hhs_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON p.subject_id = di.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND LOWER(dic.long_title) LIKE '%hyperosmolar%'
),

icu_stays_with_los AS (
  SELECT
    hp.subject_id,
    hp.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    EXTRACT(DAY FROM (i.outtime - i.intime)) AS los_days
  FROM hhs_patients hp
  JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON hp.hadm_id = i.hadm_id
  WHERE i.intime IS NOT NULL AND i.outtime IS NOT NULL
),

ct_radiography_procedures AS (
  SELECT
    pe.stay_id,
    COUNT(*) AS procedure_count
  FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%radiography%'
     OR LOWER(di.label) LIKE '%ct%'
     OR LOWER(di.label) LIKE '%computed tomography%'
     OR LOWER(di.label) LIKE '%x-ray%'
     OR LOWER(di.label) LIKE '%radiologic%'
  GROUP BY pe.stay_id
),

admission_procedure_totals AS (
  SELECT
    isw.hadm_id,
    SUM(COALESCE(cr.procedure_count, 0)) AS total_procedures
  FROM icu_stays_with_los isw
  LEFT JOIN ct_radiography_procedures cr
    ON isw.stay_id = cr.stay_id
  GROUP BY isw.hadm_id
),

binned_los AS (
  SELECT
    isw.subject_id,
    isw.hadm_id,
    isw.los_days,
    CASE
      WHEN isw.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN isw.los_days BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE 'other'
    END AS los_bin,
    apt.total_procedures
  FROM icu_stays_with_los isw
  JOIN admission_procedure_totals apt
    ON isw.hadm_id = apt.hadm_id
  WHERE isw.los_days BETWEEN 1 AND 7
)

SELECT
  los_bin,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(total_procedures) AS mean_procedures_per_admission
FROM binned_los
GROUP BY los_bin
ORDER BY los_bin;