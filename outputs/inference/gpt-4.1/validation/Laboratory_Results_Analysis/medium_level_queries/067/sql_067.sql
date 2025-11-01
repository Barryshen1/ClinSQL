WITH ami_admissions AS (
  -- Identify admissions for women age 52-62 with AMI
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND (
      -- ICD-10: I21.x, I22.x; ICD-9: 410.x
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^410'))
      OR (d.icd_version = 10 AND (REGEXP_CONTAINS(d.icd_code, r'^I21') OR REGEXP_CONTAINS(d.icd_code, r'^I22')))
    )
),
troponin_t_labs AS (
  -- Find Troponin T itemids
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  -- For each qualifying admission, get first Troponin T > 0.01 ng/mL
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_t_labs t
      ON l.itemid = t.itemid
  WHERE
    l.valuenum IS NOT NULL
)
,
first_troponin_per_admission AS (
  -- Get the first Troponin T per admission
  SELECT
    f.subject_id,
    f.hadm_id,
    f.charttime AS first_troponin_time,
    f.valuenum AS first_troponin_value
  FROM (
    SELECT
      subject_id,
      hadm_id,
      charttime,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime ASC) AS rn
    FROM first_troponin
  ) f
  WHERE f.rn = 1
    AND f.valuenum > 0.01
)
,
final_cohort AS (
  -- Join admissions and first Troponin T
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.anchor_age,
    aa.admittime,
    aa.dischtime,
    aa.hospital_expire_flag,
    ft.first_troponin_time,
    ft.first_troponin_value,
    DATETIME_DIFF(aa.dischtime, aa.admittime, DAY) AS los
  FROM
    ami_admissions aa
    JOIN first_troponin_per_admission ft
      ON aa.subject_id = ft.subject_id AND aa.hadm_id = ft.hadm_id
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  ROUND(AVG(anchor_age), 2) AS mean_age,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(MIN(first_troponin_value), 4) AS min_first_troponin,
  ROUND(MAX(first_troponin_value), 4) AS max_first_troponin,
  ROUND(AVG(first_troponin_value), 4) AS mean_first_troponin,
  ROUND(STDDEV(first_troponin_value), 4) AS stddev_first_troponin,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS in_hospital_mortality_rate
FROM
  final_cohort
;