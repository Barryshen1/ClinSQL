WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),

-- HCPCS/CPT-like events (hospital)
hcpcs_echo AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COALESCE(h.hcpcs_cd, '') AS proc_code,
    'hcpcs' AS source,
    DATE(h.chartdate) AS proc_date
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE LOWER(COALESCE(d.long_description, d.short_description, h.short_description, '')) LIKE '%echo%'
     OR LOWER(COALESCE(d.long_description, d.short_description, h.short_description, '')) LIKE '%echocardi%'
     OR LOWER(COALESCE(d.long_description, d.short_description, h.short_description, '')) LIKE '%echocardiography%'
),

-- ICD procedure table (hospital)
icd_proc_echo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COALESCE(p.icd_code, '') AS proc_code,
    'icd_procedure' AS source,
    DATE(p.chartdate) AS proc_date
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  WHERE LOWER(COALESCE(d.long_title, '')) LIKE '%echo%'
     OR LOWER(COALESCE(d.long_title, '')) LIKE '%echocardi%'
     OR LOWER(COALESCE(d.long_title, '')) LIKE '%echocardiography%'
),

-- ICU procedureevents (item labels may mention echo)
icu_proc_echo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    CAST(p.itemid AS STRING) AS proc_code,
    'icu_procedureevent' AS source,
    DATE(p.starttime) AS proc_date
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON p.itemid = d.itemid
  WHERE LOWER(COALESCE(d.label, CAST(p.value AS STRING), '')) LIKE '%echo%'
     OR LOWER(COALESCE(d.label, CAST(p.value AS STRING), '')) LIKE '%echocardi%'
     OR LOWER(COALESCE(d.label, CAST(p.value AS STRING), '')) LIKE '%echocardiography%'
),

all_echo AS (
  SELECT * FROM hcpcs_echo
  UNION ALL
  SELECT * FROM icd_proc_echo
  UNION ALL
  SELECT * FROM icu_proc_echo
),

-- Count distinct echo procedures per patient (distinct by source|code|date)
per_patient_counts AS (
  SELECT
    c.subject_id,
    COALESCE(e.cnt, 0) AS num_distinct_echo_procs
  FROM cohort c
  LEFT JOIN (
    SELECT
      subject_id,
      COUNT(DISTINCT CONCAT(source, '|' , proc_code, '|' , CAST(proc_date AS STRING))) AS cnt
    FROM all_echo
    WHERE proc_date IS NOT NULL
    GROUP BY subject_id
  ) e
  ON c.subject_id = e.subject_id
)

-- 75th percentile across patients in the cohort (including zeros)
SELECT
  CAST(
    (SELECT APPROX_QUANTILES(num_distinct_echo_procs, 100)[OFFSET(75)]
     FROM per_patient_counts)
  AS INT64) AS p75_distinct_echo_procedures_per_patient
;