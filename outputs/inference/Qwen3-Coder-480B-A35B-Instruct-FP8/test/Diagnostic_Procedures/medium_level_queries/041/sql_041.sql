WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_category,
    di.seq_num,
    CASE
      WHEN di.seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
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
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      (d.icd_version = 9 AND d.icd_code = '5770')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
    )
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

imaging_counts AS (
  SELECT
    af.hadm_id,
    af.los_category,
    af.diagnosis_type,
    COUNT(pr.icd_code) AS imaging_count
  FROM
    admissions_filtered af
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON
    af.hadm_id = pr.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON
    pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    (dp.icd_version = 9 AND dp.icd_code BETWEEN '870' AND '879')
    OR
    (dp.icd_version = 10 AND dp.icd_code LIKE 'BT1A%' OR dp.icd_code LIKE 'BT1B%')
  GROUP BY
    af.hadm_id, af.los_category, af.diagnosis_type
)

SELECT
  los_category,
  diagnosis_type,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(imaging_count) AS mean_imaging_per_admission
FROM
  imaging_counts
GROUP BY
  los_category,
  diagnosis_type
ORDER BY
  los_category,
  diagnosis_type;