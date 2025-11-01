WITH acute_pancreatitis_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    pat.gender,
    pat.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 47 AND 57
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
      OR (diag.icd_version = 9 AND diag.icd_code = '5770')
    )
),

ct_mri_procedures AS (
  SELECT
    proc.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE
    LOWER(dproc.long_title) LIKE '%ct%'
    OR LOWER(dproc.long_title) LIKE '%mri%'
  GROUP BY
    proc.hadm_id
)

SELECT
  CASE
    WHEN apa.los BETWEEN 1 AND 4 THEN 'LOS 1-4 days'
    WHEN apa.los BETWEEN 5 AND 8 THEN 'LOS 5-8 days'
    ELSE NULL
  END AS los_group,
  COUNT(DISTINCT apa.hadm_id) AS admission_count,
  ROUND(AVG(IFNULL(cmp.ct_mri_count, 0)), 2) AS mean_ct_mri_procedures_per_admission
FROM
  acute_pancreatitis_admissions apa
LEFT JOIN
  ct_mri_procedures cmp
  ON apa.hadm_id = cmp.hadm_id
WHERE
  apa.los BETWEEN 1 AND 8
GROUP BY
  los_group
HAVING
  los_group IS NOT NULL
ORDER BY
  los_group;