WITH hf_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    di.seq_num,
    CASE
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(d.long_title) LIKE '%heart failure%'
),

imaging_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS imaging_count
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%magnetic resonance%'
    OR LOWER(dp.long_title) LIKE '%computed tomography%'
  GROUP BY
    hadm_id
),

admissions_with_imaging AS (
  SELECT
    hf.hadm_id,
    hf.los_days,
    hf.diagnosis_type,
    COALESCE(img.imaging_count, 0) AS imaging_count
  FROM
    hf_admissions hf
  LEFT JOIN
    imaging_counts img
    ON hf.hadm_id = img.hadm_id
  WHERE
    hf.los_days BETWEEN 1 AND 7
)

SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  diagnosis_type,
  COUNT(*) AS admission_count,
  AVG(imaging_count) AS mean_imaging_per_admission
FROM
  admissions_with_imaging
GROUP BY
  los_group,
  diagnosis_type
ORDER BY
  los_group,
  diagnosis_type;