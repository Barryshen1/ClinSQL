WITH acs_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE 'other'
    END AS los_category,
    CASE
      WHEN d.seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_priority
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND LOWER(dd.long_title) LIKE '%acute coronary%'
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

ultrasound_counts AS (
  SELECT
    a.hadm_id,
    a.los_category,
    a.diagnosis_priority,
    COUNT(p.icd_code) AS ultrasound_count
  FROM
    acs_admissions a
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
      ON a.hadm_id = p.hadm_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
      ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY
    a.hadm_id, a.los_category, a.diagnosis_priority
)

SELECT
  los_category,
  diagnosis_priority,
  AVG(ultrasound_count) AS mean_ultrasounds_per_admission,
  MIN(ultrasound_count) AS min_ultrasounds_per_admission,
  MAX(ultrasound_count) AS max_ultrasounds_per_admission
FROM
  ultrasound_counts
GROUP BY
  los_category,
  diagnosis_priority
ORDER BY
  los_category,
  diagnosis_priority;