WITH
-- filter patients to males aged 43-53
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 43 AND 53
),

-- admissions for eligible patients
adm AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients p USING (subject_id)
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- identify AMI presence and whether it is primary (seq_num = 1) or only secondary
ami_flags AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    MAX(CASE WHEN (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21')) OR
                  (d.icd_version = 9  AND REGEXP_CONTAINS(d.icd_code, r'^410')) THEN 1 ELSE 0 END) AS any_ami,
    MAX(CASE WHEN ((d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21')) OR
                   (d.icd_version = 9  AND REGEXP_CONTAINS(d.icd_code, r'^410')))
             AND d.seq_num = 1 THEN 1 ELSE 0 END) AS primary_ami_flag,
    MAX(CASE WHEN ((d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I21')) OR
                   (d.icd_version = 9  AND REGEXP_CONTAINS(d.icd_code, r'^410')))
             AND d.seq_num > 1 THEN 1 ELSE 0 END) AS secondary_ami_flag
  FROM adm a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime
),

-- keep only admissions with AMI and classify as Primary vs Secondary
ami_admissions AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    CASE
      WHEN primary_ami_flag = 1 THEN 'Primary'
      WHEN primary_ami_flag = 0 AND secondary_ami_flag = 1 THEN 'Secondary'
      ELSE NULL
    END AS ami_type
  FROM ami_flags
  WHERE any_ami = 1
    AND (primary_ami_flag = 1 OR secondary_ami_flag = 1)
),

-- hospital HCPCS imaging events (billing-level)
hcpcs_imaging AS (
  SELECT
    h.hadm_id,
    DATE(h.chartdate) AS ev_date
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE h.hadm_id IS NOT NULL
    AND (
      -- match CT / tomography / x-ray / radiograph keywords in descriptions
      (d.long_description IS NOT NULL AND REGEXP_CONTAINS(LOWER(d.long_description),
        r'\b(ct|computed tomography|tomography|ct scan|x-?ray|xray|radiograph|radiography)\b'))
      OR
      (d.short_description IS NOT NULL AND REGEXP_CONTAINS(LOWER(d.short_description),
        r'\b(ct|computed tomography|tomography|ct scan|x-?ray|xray|radiograph|radiography)\b'))
    )
),

-- ICU procedureevents that look like imaging (from d_items)
icu_proc_imaging AS (
  SELECT
    p.hadm_id,
    DATE(p.starttime) AS ev_date
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` i
    ON p.itemid = i.itemid
  WHERE p.hadm_id IS NOT NULL
    AND i.label IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(i.label),
      r'\b(ct|computed tomography|tomography|ct scan|x-?ray|xray|radiograph|radiography)\b')
),

-- union imaging events (hcpcs + icu procedures)
imaging_events AS (
  SELECT * FROM hcpcs_imaging
  UNION ALL
  SELECT * FROM icu_proc_imaging
),

-- count imaging events per admission within admission date range
imaging_counts AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.ami_type,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS stay_days,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS stay_group,
    COALESCE(ev.cnt, 0) AS imaging_count
  FROM ami_admissions a
  LEFT JOIN (
    -- count events during admission (by date)
    SELECT ie.hadm_id, COUNT(1) AS cnt
    FROM imaging_events ie
    JOIN ami_admissions aa
      ON ie.hadm_id = aa.hadm_id
      AND ie.ev_date BETWEEN DATE(aa.admittime) AND DATE(aa.dischtime)
    GROUP BY ie.hadm_id
  ) ev
  ON a.hadm_id = ev.hadm_id
  WHERE DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
    -- ensure we only keep the two requested stay windows; will be grouped below
),

-- final aggregation: for each AMI type and stay group compute median (IQR)
final_stats AS (
  SELECT
    imaging_count_group.ami_type,
    imaging_count_group.stay_group,
    COUNT(1) AS n_admissions,
    -- approximate percentiles; APPROX_QUANTILES returns array of size 101 (0..100)
    ARRAY_AGG(imaging_count) AS _arr_for_debug, -- not used in output, but could be removed if desired
    APPROX_QUANTILES(imaging_count, 100) AS quantiles_100
  FROM imaging_counts imaging_count_group
  WHERE imaging_count_group.ami_type IS NOT NULL
    AND imaging_count_group.stay_group IS NOT NULL
  GROUP BY imaging_count_group.ami_type, imaging_count_group.stay_group
)

SELECT
  ami_type,
  stay_group,
  n_admissions,
  -- 25th percentile (approx)
  SAFE_CAST(quantiles_100[OFFSET(25)] AS INT64) AS p25_imaging_count,
  SAFE_CAST(quantiles_100[OFFSET(50)] AS INT64) AS median_imaging_count,
  SAFE_CAST(quantiles_100[OFFSET(75)] AS INT64) AS p75_imaging_count
FROM final_stats
ORDER BY ami_type, stay_group;