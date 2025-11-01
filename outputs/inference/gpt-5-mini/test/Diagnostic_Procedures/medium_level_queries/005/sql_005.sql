WITH -- Admissions of interest: female patients age 49-59, admissions with a diagnosis of ischemic stroke
stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS length_days,
    p.anchor_age,
    p.gender,
    -- Determine whether there is an ischemic-stroke diagnosis in this admission in primary position
    MAX(CASE
          WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
               OR (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code = '436'))
          THEN CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END
          ELSE 0
        END) AS stroke_primary_flag,
    -- Determine whether there is any ischemic-stroke diagnosis (primary or secondary)
    MAX(CASE
          WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
               OR (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code = '436'))
          THEN 1 ELSE 0 END) AS has_stroke_diag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.dischtime IS NOT NULL
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age, p.gender
  HAVING
    MAX(CASE
          WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
               OR (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code = '436'))
          THEN 1 ELSE 0 END) = 1
),

-- For each admission, define the length bin (1-4 or 5-8), discard other lengths
admissions_binned AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    length_days,
    CASE
      WHEN length_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN length_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS length_bin,
    CASE WHEN stroke_primary_flag = 1 THEN 'primary' ELSE 'secondary' END AS stroke_diag_type
  FROM stroke_admissions
  WHERE DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 BETWEEN 1 AND 8
),

-- Candidate diagnostic procedures from procedures_icd (ICD procedure codes) with keyword filtering on d_icd_procedures.long_title
proc_icd_filtered AS (
  SELECT
    p.hadm_id,
    p.chartdate,
    p.icd_code AS proc_code,
    dp.long_title AS proc_desc,
    CONCAT('ICDPROC|', COALESCE(p.icd_code, 'unknown'), '|', CAST(p.chartdate AS STRING)) AS proc_ref
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    -- keyword filter on description to focus on diagnostic-type procedures (imaging / endoscopy / diagnostic angiography / echo, etc.)
    (
      LOWER(COALESCE(dp.long_title, '')) LIKE '%computed tomography%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%ct %'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%magnetic resonance%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%mri%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%ultrasound%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%echocardi%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%radiograph%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%x-ray%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%xray%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%angiograph%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%angiogram%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%endoscopy%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%diagnos%'
    )
),

-- Candidate diagnostic procedures from hcpcsevents (HCPCS/CPT-like codes)
hcpcs_filtered AS (
  SELECT
    h.hadm_id,
    h.chartdate,
    h.hcpcs_cd AS proc_code,
    h.short_description AS proc_desc,
    CONCAT('HCPCS|', COALESCE(h.hcpcs_cd, 'unknown'), '|', CAST(h.chartdate AS STRING)) AS proc_ref
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE
    (
      LOWER(COALESCE(h.short_description, '')) LIKE '%ct%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%computed tomography%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%mri%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%magnetic resonance%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%ultrasound%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%echo%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%echocardi%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%radiograph%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%x-ray%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%xray%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%angiogr%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%angiog%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%endoscop%'
      OR LOWER(COALESCE(h.short_description, '')) LIKE '%diagnos%'
    )
),

-- Union the candidate procedures and count distinct procedures per admission (distinct by proc_ref)
admission_proc_counts AS (
  SELECT
    b.hadm_id,
    b.length_bin,
    b.stroke_diag_type,
    COALESCE(proc_count, 0) AS diag_proc_count
  FROM
    admissions_binned b
    LEFT JOIN (
      SELECT
        hadm_id,
        COUNT(DISTINCT proc_ref) AS proc_count
      FROM (
        SELECT hadm_id, proc_ref FROM proc_icd_filtered
        UNION ALL
        SELECT hadm_id, proc_ref FROM hcpcs_filtered
      )
      GROUP BY hadm_id
    ) pc
      ON b.hadm_id = pc.hadm_id
)

-- Final aggregation: by length_bin and stroke_diag_type compute mean, min, max diagnostic-procedure counts
SELECT
  length_bin,
  stroke_diag_type AS diagnosis_position,
  COUNT(*) AS admissions_count,
  ROUND(AVG(diag_proc_count), 2) AS mean_diagnostic_procs_per_admission,
  MIN(diag_proc_count) AS min_diagnostic_procs_per_admission,
  MAX(diag_proc_count) AS max_diagnostic_procs_per_admission
FROM
  admission_proc_counts
GROUP BY
  length_bin,
  stroke_diag_type
ORDER BY
  length_bin,
  stroke_diag_type;