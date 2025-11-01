WITH cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
ami_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
    OR (icd_version = 9 AND icd_code LIKE '410%')
),
cohort_ami AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN ami_admissions aa
    ON c.hadm_id = aa.hadm_id
  WHERE c.admission_age BETWEEN 52 AND 62
),
troponin_t AS (
  SELECT
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value,
    l.valueuom,
    l.labevent_id,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id
      ORDER BY l.charttime, l.labevent_id
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort_ami c
    ON l.hadm_id = c.hadm_id
    AND l.charttime BETWEEN c.admittime AND c.dischtime
  WHERE
    l.itemid IN (51003, 50911)  -- Troponin T item IDs
    AND l.valuenum IS NOT NULL
    AND LOWER(l.valueuom) IN ('ng/ml', 'ug/l')  -- Valid units
),
first_troponin AS (
  SELECT
    hadm_id,
    troponin_value,
    valueuom
  FROM troponin_t
  WHERE rn = 1 AND troponin_value > 0.01
)
SELECT
  COUNT(DISTINCT c.subject_id) AS patient_count,
  COUNT(DISTINCT c.hadm_id) AS admission_count,
  ROUND(AVG(c.admission_age), 1) AS mean_age,
  ROUND(AVG(DATETIME_DIFF(c.dischtime, c.admittime, DAY)), 1) AS mean_los_days,
  ROUND(AVG(ft.troponin_value), 3) AS mean_first_troponin,
  ROUND(STDDEV(ft.troponin_value), 3) AS std_first_troponin,
  MIN(ft.troponin_value) AS min_first_troponin,
  MAX(ft.troponin_value) AS max_first_troponin,
  ROUND(AVG(CAST(c.hospital_expire_flag AS FLOAT64)), 4) AS in_hospital_mortality_rate
FROM cohort_ami c
INNER JOIN first_troponin ft
  ON c.hadm_id = ft.hadm_id;