WITH pancreatitis_index AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    UPPER(pat.gender) = 'F'
    AND pat.anchor_age BETWEEN 71 AND 81
    AND LOWER(d.long_title) LIKE '%pancreatitis%'
),
-- Medication Complexity Score in first 72 hours: count distinct drugs started
-- within the first 72 hours after admission
mcs72 AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p2.drug) AS mcs72
  FROM
    pancreatitis_index AS p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p2
      ON p.subject_id = p2.subject_id
     AND p.hadm_id = p2.hadm_id
     -- medications started within the first 72 hours after admission
     AND p2.starttime >= p.admittime
     AND p2.starttime < TIMESTAMP_ADD(p.admittime, INTERVAL 72 HOUR)
  GROUP BY
    p.hadm_id
),
cohort AS (
  SELECT
    b.hadm_id,
    b.subject_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    IFNULL(m.mcs72, 0) AS mcs72
  FROM
    pancreatitis_index AS b
  LEFT JOIN
    mcs72 AS m
    ON b.hadm_id = m.hadm_id
),
calc AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.mcs72,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / 3600.0 AS los_hours,
    CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS in_hosp_mortality,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE a2.subject_id = c.subject_id
          AND a2.admittime >= c.dischtime
          AND a2.admittime < TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0 END AS readmit_30
  FROM
    cohort AS c
)
SELECT
  hadm_id,
  subject_id,
  admittime,
  dischtime,
  mcs72,
  los_hours,
  in_hosp_mortality,
  readmit_30,
  NTILE(3) OVER (ORDER BY mcs72) AS tertile
FROM
  calc
ORDER BY
  tertile,
  mcs72;