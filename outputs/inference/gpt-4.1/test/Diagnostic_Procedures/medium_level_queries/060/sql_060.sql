WITH cohort AS (
  -- Select male patients aged 49-59 with primary heart failure
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pat.anchor_age,
    pat.gender,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
      ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND diag.seq_num = 1
    AND (
      -- Heart failure ICD-10: I50.x, ICD-9: 428.x
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
      OR LOWER(d_diag.long_title) LIKE '%heart failure%'
    )
),
icu_flag AS (
  -- Flag admissions with ICU stay
  SELECT DISTINCT hadm_id, 1 AS icu_use
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
ct_mri_procs AS (
  -- CT/MRI procedures from procedures_icd
  SELECT
    proc.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
      ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE
    LOWER(d_proc.long_title) LIKE '%ct%'
    OR LOWER(d_proc.long_title) LIKE '%mri%'
  GROUP BY proc.hadm_id
),
ct_mri_hcpcs AS (
  -- CT/MRI procedures from hcpcsevents
  SELECT
    hcpcs.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpcs
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d_hcpcs
      ON hcpcs.hcpcs_cd = d_hcpcs.code
  WHERE
    LOWER(d_hcpcs.short_description) LIKE '%ct%'
    OR LOWER(d_hcpcs.short_description) LIKE '%mri%'
    OR LOWER(d_hcpcs.long_description) LIKE '%ct%'
    OR LOWER(d_hcpcs.long_description) LIKE '%mri%'
  GROUP BY hcpcs.hadm_id
),
ct_mri_total AS (
  -- Sum CT/MRI counts per admission from both sources
  SELECT
    hadm_id,
    SUM(ct_mri_count) AS ct_mri_count
  FROM (
    SELECT hadm_id, ct_mri_count FROM ct_mri_procs
    UNION ALL
    SELECT hadm_id, ct_mri_count FROM ct_mri_hcpcs
  )
  GROUP BY hadm_id
),
final AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.los_days,
    CASE
      WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN c.los_days BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group,
    IF(icu_flag.icu_use IS NULL, 'No', 'Yes') AS icu_use,
    IFNULL(ct_mri_total.ct_mri_count, 0) AS ct_mri_count
  FROM
    cohort c
    LEFT JOIN icu_flag ON c.hadm_id = icu_flag.hadm_id
    LEFT JOIN ct_mri_total ON c.hadm_id = ct_mri_total.hadm_id
  WHERE
    c.los_days BETWEEN 1 AND 7
    AND (
      (c.los_days BETWEEN 1 AND 4)
      OR (c.los_days BETWEEN 5 AND 7)
    )
)
SELECT
  los_group,
  icu_use,
  COUNT(*) AS admission_count,
  ROUND(AVG(ct_mri_count),2) AS mean_ct_mri_per_admission
FROM
  final
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group,
  icu_use
ORDER BY
  los_group,
  icu_use;