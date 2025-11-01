WITH tia_admissions AS (
  -- Identify admissions for females aged 72-82 with TIA
  SELECT
    a.hadm_id,
    a.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND (
      -- TIA ICD-10: G45.x, ICD-9: 435.x
      (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '435')
      OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'G45')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
admission_los_groups AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN 'LOS 1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN 'LOS 4-7'
      ELSE NULL
    END AS los_group
  FROM tia_admissions
  WHERE los_days BETWEEN 1 AND 7
),
icu_flags AS (
  -- Flag admissions with ICU stay
  SELECT DISTINCT
    hadm_id,
    1 AS icu_use
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
diag_imaging_procs AS (
  -- Diagnostic imaging procedures: ICD-9 87.x or 88.x
  SELECT
    pr.hadm_id,
    COUNT(*) AS num_diag_imaging_procs
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    (pr.icd_version = 9 AND (LEFT(pr.icd_code, 2) = '87' OR LEFT(pr.icd_code, 2) = '88'))
  GROUP BY pr.hadm_id
)
SELECT
  los_group,
  IFNULL(icu_use, 0) AS icu_use,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  ROUND(AVG(IFNULL(dip.num_diag_imaging_procs, 0)), 2) AS mean_diag_imaging_procs
FROM
  admission_los_groups a
  LEFT JOIN icu_flags icu
    ON a.hadm_id = icu.hadm_id
  LEFT JOIN diag_imaging_procs dip
    ON a.hadm_id = dip.hadm_id
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group,
  icu_use
ORDER BY
  los_group,
  icu_use DESC;