WITH ami_hadm AS (
  -- Identify admissions with AMI diagnosis (ICD description matching myocardial infarct / acute myocardial infarction)
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
   AND d.icd_version = dic.icd_version
  WHERE LOWER(COALESCE(dic.long_title, '')) LIKE '%myocardial infarct%'
     OR LOWER(COALESCE(dic.long_title, '')) LIKE '%acute myocardial infarction%'
),
cohort AS (
  -- Admissions for male patients age 76-86 with AMI
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN ami_hadm
    ON a.hadm_id = ami_hadm.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),
troponin_items AS (
  -- Lab itemids that look like Troponin I (label-based match)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
     OR LOWER(label) LIKE '%troponin-i%'
     OR LOWER(label) LIKE '%troponin i%'
),
first_troponin AS (
  -- For each admission in the cohort, get the first troponin I lab (by charttime) during the admission
  SELECT
    c.hadm_id,
    c.subject_id,
    le.labevent_id,
    le.charttime,
    le.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = c.hadm_id
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
    -- restrict to measurements that occurred during the admission
    AND le.charttime BETWEEN c.admittime AND c.dischtime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY le.charttime ASC, le.storetime ASC) = 1
),
quantiles AS (
  -- approximate percentiles (0..100) for first-troponin values
  SELECT APPROX_QUANTILES(valuenum, 100) AS qs
  FROM first_troponin
),
summary AS (
  SELECT
    COUNT(*) AS total_with_first_troponin,
    SUM(CASE WHEN valuenum <= 0.04 THEN 1 ELSE 0 END) AS normal_n,
    SUM(CASE WHEN valuenum > 0.04 AND valuenum < 0.40 THEN 1 ELSE 0 END) AS borderline_n,
    SUM(CASE WHEN valuenum >= 0.40 THEN 1 ELSE 0 END) AS elevated_n,
    AVG(valuenum) AS mean_troponin
  FROM first_troponin
)
SELECT
  s.total_with_first_troponin,
  s.normal_n,
  ROUND(100.0 * SAFE_DIVIDE(s.normal_n, s.total_with_first_troponin), 2) AS normal_pct,
  s.borderline_n,
  ROUND(100.0 * SAFE_DIVIDE(s.borderline_n, s.total_with_first_troponin), 2) AS borderline_pct,
  s.elevated_n,
  ROUND(100.0 * SAFE_DIVIDE(s.elevated_n, s.total_with_first_troponin), 2) AS elevated_pct,
  ROUND(s.mean_troponin, 4) AS mean_troponin,
  -- Extract median and IQR from the quantiles array (qs[OFFSET(n)] corresponds to nth percentile)
  q.qs[OFFSET(25)] AS q1_troponin,
  q.qs[OFFSET(50)] AS median_troponin,
  q.qs[OFFSET(75)] AS q3_troponin,
  q.qs[OFFSET(75)] - q.qs[OFFSET(25)] AS iqr_troponin
FROM summary s
CROSS JOIN quantiles q;