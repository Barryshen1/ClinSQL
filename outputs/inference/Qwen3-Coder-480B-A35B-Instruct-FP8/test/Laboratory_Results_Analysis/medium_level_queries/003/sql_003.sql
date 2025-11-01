WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 36 AND 46
),

ihd_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ischemic%heart%disease%'
),

first_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND LOWER(dl.label) LIKE '%high%sensitivity%'
    AND le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),

filtered_troponin AS (
  SELECT hadm_id, valuenum
  FROM first_troponin
  WHERE rn = 1
    AND valuenum > ref_range_upper
)

SELECT
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val
FROM filtered_troponin ft
JOIN ihd_admissions ia ON ft.hadm_id = ia.hadm_id
JOIN filtered_patients fp ON ia.subject_id = fp.subject_id;