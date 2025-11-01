WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 2 THEN '1-2'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 3 AND 5 THEN '3-5'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 6 AND 9 THEN '6-9'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) >= 10 THEN '>=10'
      ELSE 'Other'
    END AS los_group,
    CASE
      WHEN did.long_title LIKE '%ST elevation%' THEN 'STEMI'
      WHEN did.long_title LIKE '%non-ST elevation%' THEN 'NSTEMI'
      ELSE NULL
    END AS mi_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND did.long_title LIKE '%ST elevation (myocardial infarction)%'
    OR did.long_title LIKE '%non-ST elevation (myocardial infarction)%'
),

comorbidities AS (
  SELECT
    di.hadm_id,
    COUNT(*) AS comorbidity_count,
    MAX(CASE WHEN did.long_title LIKE '%Chronic kidney disease%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN did.long_title LIKE '%Diabetes%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE
    did.long_title LIKE '%Chronic kidney disease%'
    OR did.long_title LIKE '%Diabetes%'
  GROUP BY
    di.hadm_id
),

final_cohort AS (
  SELECT
    c.*,
    COALESCE(cm.comorbidity_count, 0) AS comorbidity_count,
    COALESCE(cm.has_ckd, 0) AS has_ckd,
    COALESCE(cm.has_diabetes, 0) AS has_diabetes,
    CASE
      WHEN COALESCE(cm.comorbidity_count, 0) BETWEEN 0 AND 1 THEN '0-1'
      WHEN COALESCE(cm.comorbidity_count, 0) = 2 THEN '2'
      WHEN COALESCE(cm.comorbidity_count, 0) >= 3 THEN '>=3'
    END AS comorbidity_group
  FROM
    cohort c
  LEFT JOIN
    comorbidities cm
    ON c.hadm_id = cm.hadm_id
  WHERE
    c.mi_type IN ('STEMI', 'NSTEMI')
)

SELECT
  mi_type,
  los_group,
  comorbidity_group,
  COUNT(*) AS n,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(has_ckd) * 100 AS ckd_prevalence_pct,
  AVG(has_diabetes) * 100 AS diabetes_prevalence_pct
FROM
  final_cohort
WHERE
  los_group != 'Other'
GROUP BY
  mi_type,
  los_group,
  comorbidity_group
ORDER BY
  mi_type,
  los_group,
  comorbidity_group;