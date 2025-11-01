WITH ischemic_stroke_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age = 82
    AND (
         (dx.icd_version = 9 AND (
             dx.icd_code LIKE '433%' OR
             dx.icd_code LIKE '434%' OR
             dx.icd_code = '436'
         ))
         OR
         (dx.icd_version = 10 AND (
             dx.icd_code LIKE 'I63%'
         ))
    )
),
admission_glucose AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    le.charttime,
    le.valuenum
  FROM ischemic_stroke_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
    AND LOWER(dl.label) LIKE '%glucose%'
    AND dl.fluid = 'Blood'
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),
first_admission_glucose AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum AS admission_glucose
  FROM (
    SELECT
      ag.*,
      ROW_NUMBER() OVER (PARTITION BY ag.hadm_id ORDER BY ag.charttime) AS rn
    FROM admission_glucose ag
  )
  WHERE rn = 1
)
SELECT
  PERCENTILE_CONT(admission_glucose, 0.75) OVER() AS p75_admission_glucose_mg_dL
FROM first_admission_glucose;