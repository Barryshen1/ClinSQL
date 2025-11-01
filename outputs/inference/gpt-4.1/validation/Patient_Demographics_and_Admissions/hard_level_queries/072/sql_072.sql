WITH cohort AS (
  -- Select index admissions meeting all criteria
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    adm.insurance,
    adm.admission_location,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year,
    EXTRACT(YEAR FROM adm.admittime) AS adm_year,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit,
    diag.icd_code,
    diag.icd_version,
    diag.seq_num,
    icd.long_title,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
      ON diag.icd_code = icd.icd_code AND diag.icd_version = icd.icd_version
  WHERE
    pat.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND adm.admission_location LIKE '%SNF%'
    AND diag.seq_num = 1
    AND (
      -- ICD-10 J96.x
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J96%')
      -- ICD-9 518.81, 518.82, 518.84
      OR (diag.icd_version = 9 AND diag.icd_code IN ('51881', '51882', '51884'))
    )
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 77 AND 87
    AND adm.hospital_expire_flag = 0
    AND adm.deathtime IS NULL
),

readmissions AS (
  -- For each index admission, find first readmission within 30 days
  SELECT
    c.subject_id,
    c.hadm_id AS index_hadm_id,
    c.dischtime AS index_dischtime,
    MIN(a.admittime) AS readmit_admittime,
    MIN(a.hadm_id) AS readmit_hadm_id
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON c.subject_id = a.subject_id
      AND a.admittime > c.dischtime
      AND a.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY
    c.subject_id, c.hadm_id, c.dischtime
),

final AS (
  -- Merge cohort and readmission info
  SELECT
    c.*,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM
    cohort c
    LEFT JOIN readmissions r
      ON c.subject_id = r.subject_id AND c.hadm_id = r.index_hadm_id
)

-- Output summary statistics
SELECT
  COUNT(*) AS n_index_admissions,
  SUM(readmitted) AS n_readmitted,
  ROUND(SUM(readmitted) / COUNT(*) * 100, 2) AS readmission_rate_percent,
  -- Median LOS for readmitted
  APPROX_QUANTILES(CASE WHEN readmitted = 1 THEN los ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted,
  -- Median LOS for not readmitted
  APPROX_QUANTILES(CASE WHEN readmitted = 0 THEN los ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted,
  -- Percent index stays >8 days (readmitted)
  ROUND(SUM(CASE WHEN readmitted = 1 AND los > 8 THEN 1 ELSE 0 END) / NULLIF(SUM(readmitted),0) * 100, 2) AS pct_los_gt8_readmitted,
  -- Percent index stays >8 days (not readmitted)
  ROUND(SUM(CASE WHEN readmitted = 0 AND los > 8 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN readmitted = 0 THEN 1 ELSE 0 END),0) * 100, 2) AS pct_los_gt8_not_readmitted
FROM
  final;