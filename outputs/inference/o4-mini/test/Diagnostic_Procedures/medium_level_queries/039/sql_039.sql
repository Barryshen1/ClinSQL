WITH cohort AS (
  SELECT
    A.subject_id,
    A.hadm_id,
    A.admittime,
    A.dischtime,
    TIMESTAMP_DIFF(A.dischtime, A.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(A.dischtime, A.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(A.dischtime, A.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
    END AS los_bin
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` A
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` P
    ON A.subject_id = P.subject_id
  WHERE
    P.gender = 'M'
    AND P.anchor_age BETWEEN 77 AND 87
),
asthma_admissions AS (
  SELECT DISTINCT
    C.*
  FROM
    cohort C
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` DI
    ON C.hadm_id = DI.hadm_id
   AND C.subject_id = DI.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` DD
    ON DI.icd_code = DD.icd_code
   AND DI.icd_version = DD.icd_version
  WHERE
    LOWER(DD.long_title) LIKE '%asthma%'
    AND LOWER(DD.long_title) LIKE '%exacerbation%'
    AND C.los_bin IS NOT NULL
),
icu_flagged AS (
  SELECT
    A.*,
    I.stay_id,
    CASE
      WHEN I.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_flag
  FROM
    asthma_admissions A
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` I
    ON A.hadm_id = I.hadm_id
   AND A.subject_id = I.subject_id
),
ct_counts AS (
  SELECT
    H.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` H
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` HC
    ON H.hcpcs_cd = HC.code
  WHERE
    LOWER(HC.long_description) LIKE '%ct%'
    OR LOWER(HC.long_description) LIKE '%mri%'
  GROUP BY
    H.hadm_id
)
SELECT
  F.icu_flag,
  F.los_bin,
  AVG(IFNULL(CC.ct_mri_count, 0)) AS mean_ct_mri_per_admission,
  MIN(IFNULL(CC.ct_mri_count, 0)) AS min_ct_mri_per_admission,
  MAX(IFNULL(CC.ct_mri_count, 0)) AS max_ct_mri_per_admission
FROM
  icu_flagged F
LEFT JOIN
  ct_counts CC
  ON F.hadm_id = CC.hadm_id
GROUP BY
  F.icu_flag,
  F.los_bin
ORDER BY
  F.icu_flag,
  F.los_bin;