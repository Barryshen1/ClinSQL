WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      -- Diabetes: ICD-9 250.x, ICD-10 E10-E14
      (d.icd_version = 9 AND d.icd_code LIKE '250%')
      OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E10' AND 'E14')
    )
    AND (
      -- Heart failure: ICD-9 428.x, ICD-10 I50.x, or text match
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
      OR LOWER(d_icd.long_title) LIKE '%heart failure%'
      OR LOWER(d_icd.long_title) LIKE '%congestive heart failure%'
    )
),

glp1_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    LOWER(p.drug) AS drug_name
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN eligible_patients ep
    ON p.subject_id = ep.subject_id AND p.hadm_id = ep.hadm_id
  WHERE LOWER(p.drug) IN (
    'liraglutide', 'semaglutide', 'exenatide', 'dulaglutide', 'lixisenatide', 'albiglutide'
  )
    AND p.starttime IS NOT NULL
),

time_windows AS (
  SELECT
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    ep.dischtime,
    CASE
      WHEN gp.starttime BETWEEN ep.admittime AND (ep.admittime + INTERVAL '24' HOUR) THEN 1
      ELSE 0
    END AS glp1_first_24h,
    CASE
      WHEN gp.starttime BETWEEN (ep.dischtime - INTERVAL '12' HOUR) AND ep.dischtime THEN 1
      ELSE 0
    END AS glp1_last_12h
  FROM eligible_patients ep
  LEFT JOIN glp1_prescriptions gp
    ON ep.subject_id = gp.subject_id AND ep.hadm_id = gp.hadm_id
)

SELECT
  ROUND(100.0 * SUM(glp1_first_24h) / COUNT(*), 2) AS percentage_first_24h,
  ROUND(100.0 * SUM(glp1_last_12h) / COUNT(*), 2) AS percentage_last_12h
FROM time_windows;