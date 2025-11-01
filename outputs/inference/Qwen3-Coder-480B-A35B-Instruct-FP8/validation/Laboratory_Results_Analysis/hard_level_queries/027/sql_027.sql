WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND d.icd_code IN ('569.3', 'K92.2')
    AND a.admittime != a.edregtime
),

labevents_72hr AS (
  SELECT
    l.hadm_id,
    l.itemid,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    l.flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    cohort c
  ON
    l.hadm_id = c.hadm_id
  WHERE
    l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND (l.ref_range_lower IS NOT NULL OR l.ref_range_upper IS NOT NULL)
),

instability_score AS (
  SELECT
    hadm_id,
    COUNT(*) AS instability_count
  FROM
    labevents_72hr
  WHERE
    flag = 'abnormal'
    OR valuenum < ref_range_lower
    OR valuenum > ref_range_upper
  GROUP BY
    hadm_id
),

quintiles AS (
  SELECT
    c.*,
    COALESCE(i.instability_count, 0) AS instability_score,
    NTILE(5) OVER (ORDER BY COALESCE(i.instability_count, 0)) AS quintile
  FROM
    cohort c
  LEFT JOIN
    instability_score i
  ON
    c.hadm_id = i.hadm_id
),

critical_labs AS (
  SELECT
    l.hadm_id,
    MAX(CASE
      WHEN l.itemid = 50813 AND l.valuenum > 4 THEN 1  -- lactate
      WHEN l.itemid = 51265 AND l.valuenum < 50 THEN 1 -- platelets
      WHEN l.itemid = 50822 AND l.valuenum < 20 THEN 1 -- potassium
      ELSE 0
    END) AS has_critical
  FROM
    labevents_72hr l
  GROUP BY
    l.hadm_id
),

quintile_stats AS (
  SELECT
    quintile,
    COUNT(*) AS patient_count,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(COALESCE(cl.has_critical, 0)) AS critical_lab_rate
  FROM
    quintiles q
  LEFT JOIN
    critical_labs cl
  ON
    q.hadm_id = cl.hadm_id
  GROUP BY
    quintile
),

overall_critical_rate AS (
  SELECT
    AVG(COALESCE(cl.has_critical, 0)) AS general_critical_lab_rate
  FROM
    quintiles q
  LEFT JOIN
    critical_labs cl
  ON
    q.hadm_id = cl.hadm_id
)

SELECT
  qs.*,
  ocr.general_critical_lab_rate
FROM
  quintile_stats qs
CROSS JOIN
  overall_critical_rate ocr
ORDER BY
  quintile;