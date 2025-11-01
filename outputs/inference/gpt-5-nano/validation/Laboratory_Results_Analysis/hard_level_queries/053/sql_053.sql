WITH scope_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON ddi.icd_code = di.icd_code AND ddi.icd_version = di.icd_version
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND p.gender = 'Male'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(ddi.long_title) LIKE '%lower gastrointestinal bleeding%'
),
lis_per_adm AS (
  SELECT
    s.hadm_id,
    s.subject_id,
    s.admittime,
    s.dischtime,
    s.deathtime,
    s.hospital_expire_flag,
    s.gender,
    s.anchor_age,
    SUM(
      CASE
        WHEN l.valuenum IS NOT NULL
             AND l.charttime >= s.admittime
             AND l.charttime < TIMESTAMP_ADD(s.admittime, INTERVAL 72 HOUR)
             AND l.ref_range_lower IS NOT NULL
             AND l.ref_range_upper IS NOT NULL
             AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
        THEN 1 ELSE 0
      END
    ) AS lis72
  FROM scope_admissions s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = s.subject_id AND l.hadm_id = s.hadm_id
  GROUP BY
    s.hadm_id, s.subject_id, s.admittime, s.dischtime, s.deathtime,
    s.hospital_expire_flag, s.gender, s.anchor_age
),
lis_threshold AS (
  SELECT DISTINCT PERCENTILE_CONT(lis72, 0.9) OVER () AS lis90
  FROM lis_per_adm
  LIMIT 1
),
topphadm AS (
  SELECT lpa.hadm_id
  FROM lis_per_adm lpa
  CROSS JOIN lis_threshold t
  WHERE lpa.lis72 >= t.lis90
),
all_inpt AS (
  SELECT lpa.*
  FROM lis_per_adm lpa
),
lab_events_all AS (
  SELECT
    a.hadm_id,
    di.label AS lab_label,
    l.valuenum,
    l.ref_range_lower AS lower,
    l.ref_range_upper AS upper,
    CASE
      WHEN l.valuenum IS NOT NULL
           AND l.ref_range_lower IS NOT NULL
           AND l.ref_range_upper IS NOT NULL
           AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      THEN 1 ELSE 0
    END AS abnormal
  FROM scope_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON di.itemid = l.itemid
  WHERE l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (
      LOWER(di.label) LIKE '%creatinine%' OR
      LOWER(di.label) LIKE '%potassium%' OR
      LOWER(di.label) LIKE '%platelet%' OR
      LOWER(di.label) LIKE '%hemoglob%' OR
      LOWER(di.label) LIKE '%white blood cell%' OR LOWER(di.label) LIKE '%wbc%'
    )
    AND a.hadm_id IN (SELECT hadm_id FROM all_inpt)
),
lab_events_top AS (
  SELECT
    a.hadm_id,
    di.label AS lab_label,
    l.valuenum,
    l.ref_range_lower AS lower,
    l.ref_range_upper AS upper,
    CASE
      WHEN l.valuenum IS NOT NULL
           AND l.ref_range_lower IS NOT NULL
           AND l.ref_range_upper IS NOT NULL
           AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      THEN 1 ELSE 0
    END AS abnormal
  FROM topphadm th
  JOIN scope_admissions a ON a.hadm_id = th.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON di.itemid = l.itemid
  WHERE l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (
      LOWER(di.label) LIKE '%creatinine%' OR
      LOWER(di.label) LIKE '%potassium%' OR
      LOWER(di.label) LIKE '%platelet%' OR
      LOWER(di.label) LIKE '%hemoglob%' OR
      LOWER(di.label) LIKE '%white blood cell%' OR LOWER(di.label) LIKE '%wbc%'
    )
),
all_lab_summary AS (
  SELECT lab_label,
         SUM(abnormal) AS abnormal_all,
         COUNT(*) AS total_all
  FROM lab_events_all
  GROUP BY lab_label
),
top_lab_summary AS (
  SELECT lab_label,
         SUM(abnormal) AS abnormal_top,
         COUNT(*) AS total_top
  FROM lab_events_top
  GROUP BY lab_label
),
lab_rates AS (
  SELECT COALESCE(a.lab_label, t.lab_label) AS lab_label,
         SAFE_DIVIDE(t.abnormal_top, t.total_top) AS toptier_rate,
         SAFE_DIVIDE(a.abnormal_all, a.total_all) AS all_rate
  FROM all_lab_summary a
  FULL OUTER JOIN top_lab_summary t
    ON a.lab_label = t.lab_label
),
top_stats AS (
  SELECT
    AVG(CASE WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS mortality_top,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/86400.0) AS avg_los_top
  FROM topphadm th
  JOIN scope_admissions sa ON sa.hadm_id = th.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON a.hadm_id = th.hadm_id
),
lis_limits AS (
  SELECT lis90 FROM lis_threshold
)

SELECT
  lis_limits.lis90 AS lis_90th_percentile_72h,
  top_stats.mortality_top,
  top_stats.avg_los_top,
  lr.lab_label,
  lr.toptier_rate,
  lr.all_rate
FROM lis_limits
CROSS JOIN top_stats
CROSS JOIN lab_rates lr
ORDER BY lab_label;