WITH copd_patients AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE UPPER(dd.long_title) LIKE '%CHRONIC OBSTRUCTIVE%'
),
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN copd_patients c
    ON a.subject_id = c.subject_id
    AND a.hadm_id = c.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 56
),
creatinine_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) IN ('blood','serum','plasma')
),
first24h_creatinine AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    AVG(l.valuenum) AS avg_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort co
    ON l.subject_id = co.subject_id
    AND l.hadm_id = co.hadm_id
  INNER JOIN creatinine_items ci
    ON l.itemid = ci.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.charttime >= co.admittime
    AND l.charttime < TIMESTAMP_ADD(co.admittime, INTERVAL 24 HOUR)
  GROUP BY l.subject_id, l.hadm_id
)
SELECT
  percentile_cont(avg_creatinine, 0.75) OVER() AS pct75_avg_creatinine
FROM first24h_creatinine;