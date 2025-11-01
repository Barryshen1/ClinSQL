WITH heart_failure_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.seq_num = 1
    AND d.icd_code LIKE 'I50%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),
los_icu AS (
  SELECT
    hfa.hadm_id,
    TIMESTAMP_DIFF(hfa.dischtime, hfa.admittime, DAY) AS los,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu
  FROM
    heart_failure_admissions hfa
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON hfa.hadm_id = i.hadm_id
),
ct_mri_count AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE
    d.long_description LIKE '%CT%' OR d.long_description LIKE '%MRI%'
  GROUP BY
    h.hadm_id
)
SELECT
  has_icu,
  CASE
    WHEN los BETWEEN 1 AND 4 THEN '1-4'
    WHEN los BETWEEN 5 AND 7 THEN '5-7'
  END AS los_category,
  COUNT(*) AS admission_count,
  AVG(COALESCE(c.ct_mri_count, 0)) AS mean_ct_mri
FROM
  los_icu l
LEFT JOIN
  ct_mri_count c
  ON l.hadm_id = c.hadm_id
WHERE
  l.los BETWEEN 1 AND 7
GROUP BY
  has_icu,
  los_category;