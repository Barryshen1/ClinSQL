WITH male_age_cohort AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 83 AND 93
),
chestpain_ami_hadm AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%myocardial infarction%'
     OR LOWER(dd.long_title) LIKE '%chest pain%'
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    le.ref_range_upper,
    ROW_NUMBER() OVER(PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND le.valuenum > le.ref_range_upper
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age AS age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    ft.valuenum AS troponin_value
  FROM male_age_cohort p
  JOIN chestpain_ami_hadm cp
    ON p.subject_id = cp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON cp.hadm_id = a.hadm_id
   AND cp.subject_id = a.subject_id
  JOIN first_troponin ft
    ON a.hadm_id = ft.hadm_id
   AND a.subject_id = ft.subject_id
   AND ft.rn = 1
)
SELECT
  COUNT(DISTINCT subject_id) AS N,
  AVG(age) AS mean_age,
  AVG(los_days) AS mean_los_days,
  AVG(troponin_value) AS mean_troponin,
  MIN(troponin_value) AS min_troponin,
  MAX(troponin_value) AS max_troponin
FROM cohort;