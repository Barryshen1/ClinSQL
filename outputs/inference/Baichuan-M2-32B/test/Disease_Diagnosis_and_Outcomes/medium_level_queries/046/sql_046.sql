WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN (
    SELECT DISTINCT
      d1.subject_id,
      d1.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2
      ON d1.icd_code = d2.icd_code AND d1.icd_version = d2.icd_version
    WHERE
      d2.long_title LIKE '%heart failure%' 
      OR d1.icd_code IN ('I10', 'I11', 'I13', 'I25.1', 'I50.9', 'I50.10', 'I50.11', 'I50.12', 'I50.13', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'I50.90', 'I50.91', 'I50.92', 'I50.93')
  ) hf
    ON a.subject_id = hf.subject_id AND a.hadm_id = hf.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
comorbidity_counts AS (
  SELECT
    d1.hadm_id,
    COUNT(DISTINCT d1.icd_code) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2
    ON d1.icd_code = d2.icd_code AND d1.icd_version = d2.icd_version
  WHERE
    d2.long_title NOT LIKE '%heart failure%'
    AND d1.icd_code NOT IN ('I10', 'I11', 'I13', 'I25.1', 'I50.9', 'I50.10', 'I50.11', 'I50.12', 'I50.13', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'I50.90', 'I50.91', 'I50.92', 'I50.93')
  GROUP BY
    d1.hadm_id
)
SELECT
  icu_status,
  los_group,
  AVG(hospital_expire_flag) AS mortality_rate,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(50)] AS median_los,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM
  hf_admissions h
LEFT JOIN
  comorbidity_counts c
  ON h.hadm_id = c.hadm_id
LEFT JOIN (
  SELECT
    hadm_id,
    CASE
      WHEN los <= 3 THEN '≤3'
      WHEN los BETWEEN 4 AND 6 THEN '4–6'
      WHEN los BETWEEN 7 AND 10 THEN '7–10'
      ELSE '>10'
    END AS los_group
  FROM hf_admissions
) g
  ON h.hadm_id = g.hadm_id
GROUP BY
  icu_status,
  los_group
ORDER BY
  icu_status,
  los_group;