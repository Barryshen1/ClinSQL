WITH pancreatitis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    d.seq_num AS diagnosis_seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      -- ICD-10 K85.x or ICD-9 577.0
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^K85'))
      OR (d.icd_version = 9 AND d.icd_code = '5770')
    )
),
radiology_ct_procedures AS (
  SELECT
    pr.hadm_id,
    COUNTIF(
      LOWER(dp.long_title) LIKE '%ct%'
      OR LOWER(dp.long_title) LIKE '%radiography%'
      OR LOWER(dp.long_title) LIKE '%computed tomography%'
      OR LOWER(dp.long_title) LIKE '%x-ray%'
    ) AS radiology_ct_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  GROUP BY
    pr.hadm_id
),
admission_summary AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.diagnosis_seq_num,
    CASE
      WHEN pa.diagnosis_seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type,
    TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    rc.radiology_ct_count
  FROM
    pancreatitis_admissions pa
    LEFT JOIN radiology_ct_procedures rc
      ON pa.hadm_id = rc.hadm_id
)
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN 'LOS 1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN 'LOS 4-7'
    ELSE NULL
  END AS los_bin,
  diagnosis_type,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(AVG(IFNULL(radiology_ct_count, 0)), 2) AS mean_radiology_cts_per_admission
FROM
  admission_summary
WHERE
  los_days BETWEEN 1 AND 7
GROUP BY
  los_bin,
  diagnosis_type
ORDER BY
  los_bin,
  diagnosis_type;