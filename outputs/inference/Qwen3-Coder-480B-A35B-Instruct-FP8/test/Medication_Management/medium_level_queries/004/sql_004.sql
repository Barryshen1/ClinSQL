WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
),

diabetes AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (di.icd_version = 9 AND di.icd_code LIKE '250.%')
    OR (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
),

heart_failure AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (di.icd_version = 9 AND di.icd_code LIKE '428%')
    OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
),

target_patients AS (
  SELECT
    c.*
  FROM
    cohort c
  JOIN
    diabetes d ON c.hadm_id = d.hadm_id
  JOIN
    heart_failure hf ON c.hadm_id = hf.hadm_id
),

glp1_meds AS (
  SELECT DISTINCT
    drug
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE
    LOWER(drug) IN (
      'liraglutide', 'exenatide', 'dulaglutide', 'semaglutide',
      'saxenda', 'byetta', 'trulicity', 'ozempic'
    )
),

glp1_prescriptions AS (
  SELECT
    tp.hadm_id,
    MIN(pr.starttime) AS first_glp1_start,
    MAX(COALESCE(pr.stoptime, tp.dischtime)) AS last_glp1_stop
  FROM
    target_patients tp
  JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON tp.hadm_id = pr.hadm_id
  JOIN
    glp1_meds g
    ON LOWER(pr.drug) = LOWER(g.drug)
  WHERE
    pr.starttime IS NOT NULL
  GROUP BY
    tp.hadm_id
),

analysis_flags AS (
  SELECT
    tp.hadm_id,
    CASE
      WHEN gp.first_glp1_start IS NOT NULL
        AND DATETIME_DIFF(gp.first_glp1_start, tp.admittime, HOUR) <= 72
      THEN 1
      ELSE 0
    END AS started_glp1_within_72h,
    CASE
      WHEN gp.last_glp1_stop IS NOT NULL
        AND DATETIME_DIFF(tp.dischtime, gp.last_glp1_stop, HOUR) <= 48
      THEN 1
      ELSE 0
    END AS on_glp1_in_last_48h
  FROM
    target_patients tp
  LEFT JOIN
    glp1_prescriptions gp
    ON tp.hadm_id = gp.hadm_id
)

SELECT
  COUNT(*) AS total_patients,
  AVG(started_glp1_within_72h) * 100 AS pct_started_within_72h,
  AVG(on_glp1_in_last_48h) * 100 AS pct_on_in_last_48h,
  (AVG(started_glp1_within_72h) - AVG(on_glp1_in_last_48h)) * 100 AS net_change
FROM
  analysis_flags;