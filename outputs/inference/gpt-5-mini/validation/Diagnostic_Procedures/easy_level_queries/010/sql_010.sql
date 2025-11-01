WITH male_84_94 AS (
  -- male patients aged 84-94 (anchor_age provided in patients table)
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 84 AND 94
),
admissions_f AS (
  -- admissions for the filtered patients, with admit/discharge dates
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE(a.admittime) AS admit_date,
    DATE(a.dischtime) AS discharge_date
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_84_94 p USING(subject_id)
),
candidate_procs AS (
  -- HCPCS/HCPCS-like billed procedures
  SELECT
    subject_id,
    hadm_id,
    COALESCE(hcpcs_cd, '') AS proc_code,
    LOWER(COALESCE(short_description, '')) AS proc_desc,
    DATE(chartdate) AS event_date,
    'hcpcsevents' AS src
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE LOWER(COALESCE(short_description, '')) LIKE '%echo%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%echocardi%'
  
  UNION ALL

  -- ICD procedures (textual description from d_icd_procedures)
  SELECT
    p.subject_id,
    p.hadm_id,
    COALESCE(p.icd_code, '') AS proc_code,
    LOWER(COALESCE(d.long_title, '')) AS proc_desc,
    DATE(p.chartdate) AS event_date,
    'procedures_icd' AS src
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(COALESCE(d.long_title, '')) LIKE '%echo%'
     OR LOWER(COALESCE(d.long_title, '')) LIKE '%echocardi%'

  UNION ALL

  -- ICU-charted procedure events (value text may describe the procedure)
  SELECT
    subject_id,
    hadm_id,
    CAST(itemid AS STRING) AS proc_code,
    LOWER(COALESCE(CAST(value AS STRING), '')) AS proc_desc,
    DATE(starttime) AS event_date,
    'procedureevents' AS src
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE LOWER(COALESCE(CAST(value AS STRING), '')) LIKE '%echo%'
     OR LOWER(COALESCE(CAST(value AS STRING), '')) LIKE '%echocardi%'
),
procs_in_admission AS (
  -- keep only candidate procedures that fall within the admission dates
  SELECT
    a.subject_id,
    a.hadm_id,
    c.src,
    c.proc_code,
    c.proc_desc,
    c.event_date
  FROM candidate_procs c
  JOIN admissions_f a
    ON c.subject_id = a.subject_id
   AND c.hadm_id = a.hadm_id
  WHERE c.event_date BETWEEN a.admit_date AND a.discharge_date
),
counts_per_admission AS (
  -- count distinct procedures per admission (use src+proc_code to distinguish codes across sources)
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT CONCAT(src, '||', proc_code)) AS distinct_echo_proc_count
  FROM procs_in_admission
  GROUP BY subject_id, hadm_id
)

-- final: maximum distinct echocardiography procedures per hospitalization among males 84-94
SELECT
  MAX(distinct_echo_proc_count) AS max_distinct_echocardiography_procedures_per_hospitalization
FROM counts_per_admission;