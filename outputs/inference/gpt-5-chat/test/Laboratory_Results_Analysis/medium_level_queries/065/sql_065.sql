WITH ami_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE ( (d.icd_version = 9 AND d.icd_code LIKE '410%')
       OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
        )
),
male_age_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 49 AND 59
),
troponin_t_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_elevated_trop AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_itemids ti
    ON l.itemid = ti.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.valuenum > 0.04
)
,
first_per_hadm AS (
  SELECT subject_id, hadm_id, valuenum
  FROM (
    SELECT fe.subject_id, fe.hadm_id, fe.valuenum,
           ROW_NUMBER() OVER (PARTITION BY fe.subject_id, fe.hadm_id ORDER BY fe.charttime) AS rn
    FROM first_elevated_trop fe
    JOIN ami_admissions a
      ON fe.subject_id = a.subject_id AND fe.hadm_id = a.hadm_id
    JOIN male_age_cohort m
      ON fe.subject_id = m.subject_id
  )
  WHERE rn = 1
)
SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_value,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] -
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_value
FROM first_per_hadm;