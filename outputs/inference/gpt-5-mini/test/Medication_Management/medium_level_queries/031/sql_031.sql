WITH cohort_adm AS (
  -- male inpatients aged 53-63 at admission (using anchor_age) with valid discharge time
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.dischtime IS NOT NULL
),

diag_flags AS (
  -- per-admission flags for diabetes and heart failure using diagnosis descriptions
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%' OR LOWER(COALESCE(dd.long_title, '')) LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  GROUP BY
    d.hadm_id
),

cohort AS (
  -- admissions meeting gender/age + both diagnosis requirements
  SELECT
    c.*
  FROM
    cohort_adm c
  JOIN
    diag_flags df
  ON
    c.hadm_id = df.hadm_id
  WHERE
    df.has_diabetes = 1
    AND df.has_hf = 1
),

glp_candidates AS (
  -- union medication/order/administration sources for GLP-1 RA names (exclude known oral semaglutide 'rybelsus')
  SELECT
    hadm_id,
    starttime AS med_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    starttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(drug, '')), r'(liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|albiglutide|bydureon|victoza|trulicity|ozempic)')
    AND NOT REGEXP_CONTAINS(LOWER(COALESCE(drug, '')), r'rybelsus')
  UNION ALL
  SELECT
    hadm_id,
    starttime AS med_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE
    starttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(medication, '')), r'(liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|albiglutide|bydureon|victoza|trulicity|ozempic)')
    AND NOT REGEXP_CONTAINS(LOWER(COALESCE(medication, '')), r'rybelsus')
  UNION ALL
  SELECT
    hadm_id,
    charttime AS med_time
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE
    charttime IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(medication, '')), r'(liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|albiglutide|bydureon|victoza|trulicity|ozempic)')
    AND NOT REGEXP_CONTAINS(LOWER(COALESCE(medication, '')), r'rybelsus')
),

med_first AS (
  -- earliest GLP-1 RA time per admission (across sources)
  SELECT
    hadm_id,
    MIN(med_time) AS first_med_time
  FROM
    glp_candidates
  GROUP BY
    hadm_id
),

analysis AS (
  -- join cohort admissions with earliest med time and compute window flags
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    m.first_med_time,
    -- initiated within first 24 hours of admission (must occur during the admission)
    CASE
      WHEN m.first_med_time IS NOT NULL
       AND m.first_med_time >= c.admittime
       AND m.first_med_time <= c.dischtime
       AND TIMESTAMP_DIFF(m.first_med_time, c.admittime, MINUTE) <= 24 * 60
      THEN 1 ELSE 0
    END AS init_first24,
    -- initiated within final 12 hours before discharge (must occur during the admission)
    CASE
      WHEN m.first_med_time IS NOT NULL
       AND m.first_med_time <= c.dischtime
       AND m.first_med_time >= c.admittime
       AND TIMESTAMP_DIFF(c.dischtime, m.first_med_time, MINUTE) <= 12 * 60
      THEN 1 ELSE 0
    END AS init_last12
  FROM
    cohort c
  LEFT JOIN
    med_first m
  ON
    c.hadm_id = m.hadm_id
)

SELECT
  COUNT(*) AS total_admissions_in_cohort,
  SUM(init_first24) AS n_initiated_first_24h,
  SAFE_DIVIDE(100.0 * SUM(init_first24), COUNT(*)) AS pct_initiated_first_24h,
  SUM(init_last12) AS n_initiated_final_12h,
  SAFE_DIVIDE(100.0 * SUM(init_last12), COUNT(*)) AS pct_initiated_final_12h
FROM
  analysis;