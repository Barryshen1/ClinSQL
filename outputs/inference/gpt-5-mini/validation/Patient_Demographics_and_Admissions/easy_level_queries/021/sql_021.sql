WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
)
SELECT
  COUNT(*) AS cohort_size,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(
    100 * SAFE_DIVIDE(
      SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END),
      COUNT(*)
    ),
    2
  ) AS mortality_pct
FROM
  first_admissions fa
WHERE
  rn = 1
  AND gender = 'F'
  AND anchor_age BETWEEN 83 AND 93
  AND EXISTS (
    SELECT 1
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON
      d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
    WHERE
      d.hadm_id = fa.hadm_id
      AND LOWER(di.long_title) LIKE '%pneumonia%'
  );