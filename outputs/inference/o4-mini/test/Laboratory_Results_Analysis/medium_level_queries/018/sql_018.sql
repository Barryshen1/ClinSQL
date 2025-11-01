WITH acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9
         AND (d.icd_code LIKE '410%'    /* Acute MI */
              OR d.icd_code = '4111'     /* Unstable angina */
             )
        )
),
elderly_males AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM acs_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),
index_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    ref_range_upper,
    CASE
      WHEN valuenum <= ref_range_upper THEN 'normal'
      WHEN valuenum <= 2 * ref_range_upper THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM first_troponin
  WHERE rn = 1
),
cohort AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.dischtime,
    tt.valuenum,
    tt.ref_range_upper,
    tt.category,
    TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) AS los_days
  FROM elderly_males e
  JOIN index_troponin tt
    ON e.hadm_id = tt.hadm_id
)
SELECT
  category,
  COUNT(*) AS n_patients,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_cohort,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM cohort
GROUP BY category
ORDER BY category;