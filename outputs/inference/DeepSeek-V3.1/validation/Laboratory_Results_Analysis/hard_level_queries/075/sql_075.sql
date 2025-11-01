WITH cohort AS (
  -- Male patients aged 42-52 with DVT
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I82%') OR
      (diag.icd_version = 9 AND diag.icd_code LIKE '4534%')
    )
),

labs_list AS (
  -- Define the labs of interest with their itemids
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE itemid IN (50824, 50822, 50825, 50882, 50912, 50931, 51300, 51301)
),

labs_72hr AS (
  -- Get lab measurements within 72 hours of admission for the cohort
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    le.itemid, 
    le.valuenum, 
    le.ref_range_lower, 
    le.ref_range_upper,
    -- Flag if abnormal (outside reference range)
    CASE 
      WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1 
      ELSE 0 
    END AS is_abnormal
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id AND c.hadm_id = le.hadm_id
  INNER JOIN labs_list ll ON le.itemid = ll.itemid
  WHERE le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
),

instability_scores AS (
  -- Calculate instability score per patient (sum of abnormal flags per lab type)
  SELECT 
    subject_id, 
    hadm_id,
    SUM(is_abnormal) AS score
  FROM (
    -- For each lab type, if at least one measurement is abnormal, count 1
    SELECT 
      subject_id, 
      hadm_id, 
      itemid, 
      MAX(is_abnormal) AS is_abnormal
    FROM labs_72hr
    GROUP BY subject_id, hadm_id, itemid
  )
  GROUP BY subject_id, hadm_id
),

percentile_95 AS (
  -- Compute the 95th percentile score
  SELECT APPROX_QUANTILES(score, 100)[OFFSET(95)] AS p95
  FROM instability_scores
),

high_risk_cohort AS (
  -- Get the high-risk patients (score >= 95th percentile)
  SELECT 
    c.*, 
    isc.score
  FROM cohort c
  INNER JOIN instability_scores isc
    ON c.subject_id = isc.subject_id AND c.hadm_id = isc.hadm_id
  CROSS JOIN percentile_95 p
  WHERE isc.score >= p.p95
),

-- For critical lab rates comparison: we need to compute for each lab the proportion of abnormal in high-risk vs all inpatients
all_inpatients AS (
  -- All distinct inpatients (hadm_id) from admissions
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

labs_72hr_all AS (
  -- Lab measurements within 72h for all inpatients
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    le.itemid,
    MAX(CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1 ELSE 0 END) AS is_abnormal
  FROM all_inpatients a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON a.subject_id = adm.subject_id AND a.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id AND a.hadm_id = le.hadm_id
  INNER JOIN labs_list ll ON le.itemid = ll.itemid
  WHERE le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
  GROUP BY a.subject_id, a.hadm_id, le.itemid
),

lab_rates_high_risk AS (
  -- For each lab, proportion of high-risk patients with abnormal value
  SELECT 
    itemid,
    COUNT(DISTINCT subject_id) AS total_patients,
    SUM(is_abnormal) AS abnormal_count,
    SUM(is_abnormal) / COUNT(DISTINCT subject_id) AS abnormal_rate
  FROM (
    SELECT 
      hrc.subject_id, 
      hrc.hadm_id, 
      ll.itemid,
      COALESCE(MAX(la.is_abnormal), 0) AS is_abnormal  -- If lab not measured, assume normal? But we only consider labs that were measured.
    FROM high_risk_cohort hrc
    CROSS JOIN labs_list ll
    LEFT JOIN labs_72hr_all la
      ON hrc.subject_id = la.subject_id AND hrc.hadm_id = la.hadm_id AND ll.itemid = la.itemid
    GROUP BY hrc.subject_id, hrc.hadm_id, ll.itemid
  )
  GROUP BY itemid
),

lab_rate_all_inpatients AS (
  -- For each lab, proportion of all inpatients with abnormal value
  SELECT 
    itemid,
    COUNT(DISTINCT subject_id) AS total_patients,
    SUM(is_abnormal) AS abnormal_count,
    SUM(is_abnormal) / COUNT(DISTINCT subject_id) AS abnormal_rate
  FROM labs_72hr_all
  GROUP BY itemid
)

-- Final output
SELECT 
  (SELECT p95 FROM percentile_95) AS percentile_95_score,
  (SELECT COUNT(*) FROM high_risk_cohort) AS high_risk_count,
  (SELECT AVG(DATE_DIFF(dischtime, admittime, DAY)) FROM high_risk_cohort) AS mean_los_days,
  (SELECT SUM(hospital_expire_flag) FROM high_risk_cohort) AS mortality_count,
  (SELECT SUM(hospital_expire_flag) / COUNT(*) FROM high_risk_cohort) AS mortality_rate,
  lr.itemid,
  di.label AS lab_name,
  lr.total_patients AS high_risk_total,
  lr.abnormal_count AS high_risk_abnormal,
  lr.abnormal_rate AS high_risk_rate,
  la.total_patients AS all_inpatients_total,
  la.abnormal_count AS all_inpatients_abnormal,
  la.abnormal_rate AS all_inpatients_rate
FROM lab_rates_high_risk lr
INNER JOIN lab_rate_all_inpatients la ON lr.itemid = la.itemid
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON lr.itemid = di.itemid
ORDER BY lr.itemid;