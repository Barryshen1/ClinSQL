WITH FirstHFAdmission AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND d.icd_code LIKE '398%' -- Heart failure codes
    AND d.seq_num = 1 -- First diagnosis listed
),
Readmissions AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.dischtime,
    a.admittime AS readmission_time
  FROM
    FirstHFAdmission AS f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON f.subject_id = a.subject_id
  WHERE
    a.hadm_id != f.hadm_id
    AND a.admittime > f.dischtime
    AND a.admittime <= DATETIME_ADD(f.dischtime, INTERVAL 30 DAY)
)
SELECT
  COUNT(DISTINCT r.subject_id) / COUNT(DISTINCT f.subject_id) AS readmission_rate
FROM
  FirstHFAdmission AS f
LEFT JOIN
  Readmissions AS r ON f.subject_id = r.subject_id;