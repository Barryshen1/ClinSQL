WITH heart_failure_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
     AND d.seq_num    = 1
     AND d.icd_version = 10
     AND d.icd_code LIKE 'I50%'    -- primary heart failure
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
los_strata AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group
  FROM heart_failure_admissions
),
icu_flag AS (
  SELECT
    ls.*,
    CASE
      WHEN icu.stay_id IS NOT NULL THEN 'Yes'
      ELSE 'No'
    END AS icu_use
  FROM los_strata ls
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id, stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
    ON ls.subject_id = icu.subject_id
   AND ls.hadm_id    = icu.hadm_id
),
ct_mri_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    LOWER(short_description) LIKE '%ct%'
    OR LOWER(short_description) LIKE '%mri%'
  GROUP BY hadm_id
)
SELECT
  icu_use,
  los_group,
  COUNT(DISTINCT icu.hadm_id) AS admission_count,
  ROUND(AVG(IFNULL(c.ct_mri_count, 0)), 2) AS mean_ct_mri_per_admission
FROM
  icu_flag icu
LEFT JOIN ct_mri_counts c
  ON icu.hadm_id = c.hadm_id
WHERE
  los_group IS NOT NULL
GROUP BY
  icu_use,
  los_group
ORDER BY
  icu_use,
  los_group;