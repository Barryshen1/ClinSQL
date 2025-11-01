WITH cohort AS (
  -- Select admissions for female patients aged 45-55, LOS 1-7 days
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

hf_admissions AS (
  -- Identify HF admissions and diagnosis type (primary/secondary)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.los_days,
    CASE
      WHEN MIN(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS hf_diag_type
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-10 HF: I50.x, ICD-9 HF: 428.x
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
  GROUP BY
    c.subject_id, c.hadm_id, c.anchor_age, c.gender, c.los_days
),

ct_mri_procs AS (
  -- Identify CT/MRI procedures per admission
  SELECT
    p.hadm_id,
    COUNTIF(
      LOWER(dp.long_title) LIKE '%ct%'
      OR LOWER(dp.long_title) LIKE '%mri%'
    ) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ct%'
    OR LOWER(dp.long_title) LIKE '%mri%'
  GROUP BY
    p.hadm_id
),

final AS (
  -- Merge HF admissions with CT/MRI counts (include zero counts)
  SELECT
    h.subject_id,
    h.hadm_id,
    h.anchor_age,
    h.gender,
    h.los_days,
    h.hf_diag_type,
    CASE
      WHEN h.los_days BETWEEN 1 AND 3 THEN '1-3'
      ELSE '4-7'
    END AS los_bucket,
    COALESCE(c.ct_mri_count, 0) AS ct_mri_count
  FROM
    hf_admissions h
    LEFT JOIN ct_mri_procs c
      ON h.hadm_id = c.hadm_id
)

SELECT
  hf_diag_type,
  los_bucket,
  COUNT(*) AS n_admissions,
  AVG(ct_mri_count) AS mean_ct_mri_per_admission,
  MIN(ct_mri_count) AS min_ct_mri_per_admission,
  MAX(ct_mri_count) AS max_ct_mri_per_admission
FROM
  final
GROUP BY
  hf_diag_type,
  los_bucket
ORDER BY
  hf_diag_type,
  los_bucket;