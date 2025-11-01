WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND LOWER(dd.long_title) LIKE '%lower%'
    AND LOWER(dd.long_title) LIKE '%gastro%'
    AND (LOWER(dd.long_title) LIKE '%hemorrhage%' OR LOWER(dd.long_title) LIKE '%bleed%')
),
lab_window AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    l.labevent_id,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    l.flag,
    CASE
      WHEN l.valuenum IS NULL THEN 0
      WHEN l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower THEN 1
      WHEN l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper THEN 1
      WHEN LOWER(l.flag) LIKE '%abnormal%' THEN 1
      WHEN LOWER(l.flag) LIKE '%high%' THEN 1
      WHEN LOWER(l.flag) LIKE '%low%' THEN 1
      ELSE 0
    END AS is_abnormal
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id
    AND c.hadm_id = l.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
),
lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNTIF(is_abnormal=1) AS lab_instability_score,
    COUNT(*) AS total_labs,
    SAFE_DIVIDE(COUNTIF(is_abnormal=1), COUNT(*)) AS critical_lab_rate
  FROM lab_window
  GROUP BY subject_id, hadm_id
),
quintiles AS (
  SELECT
    ls.subject_id,
    ls.hadm_id,
    ls.lab_instability_score,
    ls.total_labs,
    ls.critical_lab_rate,
    NTILE(5) OVER (ORDER BY ls.lab_instability_score) AS quintile
  FROM lab_scores ls
),
cohort_metrics AS (
  SELECT
    q.quintile,
    COUNT(*) AS admissions,
    AVG(DATETIME_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los_days,
    AVG(c.hospital_expire_flag) AS mortality_rate,
    AVG(q.critical_lab_rate) AS avg_critical_lab_rate
  FROM quintiles q
  JOIN cohort c
    ON q.subject_id = c.subject_id
    AND q.hadm_id = c.hadm_id
  GROUP BY quintile
),
general_inpatient_rate AS (
  SELECT
    SAFE_DIVIDE(COUNTIF(is_abnormal=1), COUNT(*)) AS general_critical_lab_rate
  FROM (
    SELECT
      l.labevent_id,
      l.valuenum,
      l.ref_range_lower,
      l.ref_range_upper,
      l.flag,
      CASE
        WHEN l.valuenum IS NULL THEN 0
        WHEN l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower THEN 1
        WHEN l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper THEN 1
        WHEN LOWER(l.flag) LIKE '%abnormal%' THEN 1
        WHEN LOWER(l.flag) LIKE '%high%' THEN 1
        WHEN LOWER(l.flag) LIKE '%low%' THEN 1
        ELSE 0
      END AS is_abnormal
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  )
)
SELECT
  cm.quintile,
  cm.admissions,
  cm.avg_los_days,
  cm.mortality_rate,
  cm.avg_critical_lab_rate,
  gir.general_critical_lab_rate
FROM cohort_metrics cm
CROSS JOIN general_inpatient_rate gir
ORDER BY cm.quintile;