WITH acs_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      d.icd_code LIKE 'I21%'  -- Acute myocardial infarction
      OR d.icd_code LIKE 'I22%'  -- Subsequent myocardial infarction
      OR d.icd_code LIKE 'I24%'  -- Other acute ischemic heart disease
      OR d.icd_code = 'I25.1'   -- Chronic ischemic heart disease (often included in ACS cohorts)
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_hospital_los_days
FROM
  acs_admissions;