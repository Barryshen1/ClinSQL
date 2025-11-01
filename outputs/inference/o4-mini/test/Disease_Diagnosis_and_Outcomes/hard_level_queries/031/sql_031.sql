WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_primary
      USING(subject_id, hadm_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 85 AND 95
    AND d_primary.seq_num = 1
    AND d_primary.icd_version = 10
    AND (
      STARTS_WITH(d_primary.icd_code, 'J45')
      OR d_primary.icd_code = 'J46'
    )
),
comorbidity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag,
    COUNT(DISTINCT d.icd_code) AS comorbidity_score,
    -- flags for complications
    MAX(IF(d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I'), 1, 0)) AS has_cardiovascular,
    MAX(IF(d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'G'), 1, 0)) AS has_neurologic
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
  WHERE
    d.seq_num > 1
    AND d.icd_version = 10
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY comorbidity_score) AS quartile
  FROM
    comorbidity
)
SELECT
  quartile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(hospital_expire_flag), 3) AS in_hospital_mortality_rate,
  ROUND(AVG(has_cardiovascular), 3) AS cardiovascular_complication_rate,
  ROUND(AVG(has_neurologic), 3) AS neurologic_complication_rate
FROM
  quartiles
GROUP BY
  quartile
ORDER BY
  quartile;