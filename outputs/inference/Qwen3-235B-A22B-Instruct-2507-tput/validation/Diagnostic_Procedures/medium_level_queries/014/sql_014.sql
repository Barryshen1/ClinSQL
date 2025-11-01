WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    di.seq_num,
    di.icd_code,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY di.seq_num) AS rn_diag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 83 AND 93
    AND d.long_title LIKE '%Acute coronary syndrome%'
    AND a.dischtime IS NOT NULL
),
acs_cohort AS (
  SELECT
    hadm_id,
    subject_id,
    age,
    los_days,
    CASE
      WHEN MIN(seq_num) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS acs_diagnosis_type
  FROM
    patient_admissions
  GROUP BY
    hadm_id, subject_id, age, los_days
),
ultrasound_proc AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON
    h.hcpcs_cd = d.code
  WHERE
    LOWER(d.category) = 'ultrasound'
  GROUP BY
    h.hadm_id
),
combined AS (
  SELECT
    acs.hadm_id,
    acs.los_days,
    acs.acs_diagnosis_type,
    CASE
      WHEN acs.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN acs.los_days BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_group,
    COALESCE(ultrasound_count, 0) AS ultrasound_count
  FROM
    acs_cohort acs
  LEFT JOIN
    ultrasound_proc ul
  ON
    acs.hadm_id = ul.hadm_id
  WHERE
    acs.los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  acs_diagnosis_type,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds,
  COUNT(*) AS admission_count
FROM
  combined
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group, acs_diagnosis_type
ORDER BY
  los_group, acs_diagnosis_type;