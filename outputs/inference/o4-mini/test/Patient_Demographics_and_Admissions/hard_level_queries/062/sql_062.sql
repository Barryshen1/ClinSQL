WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (
      PARTITION BY a.subject_id
      ORDER BY a.admittime
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
    AND d.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY'
    AND LOWER(dd.long_title) LIKE '%acute cholecystitis%'
)
SELECT
  COUNT(*) AS total_index_admissions
FROM
  cohort_admissions
WHERE
  rn = 1;