WITH patient_age AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

aki_diagnoses AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.seq_num,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS aki_diagnosis_type
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    CAST(di.icd_code AS STRING) = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    d.icd_version = 10
    AND d.icd_code LIKE 'N17%'
),

admissions_with_aki AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.los_days,
    ak.aki_diagnosis_type
  FROM
    patient_age pa
  INNER JOIN
    aki_diagnoses ak
  ON
    pa.subject_id = ak.subject_id AND pa.hadm_id = ak.hadm_id
  WHERE
    pa.los_days BETWEEN 1 AND 7
),

imaging_studies AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d
  ON
    h.hcpcs_cd = d.code
  WHERE
    d.category = 'IMAGING'
  GROUP BY
    h.hadm_id
),

admissions_with_imaging AS (
  SELECT
    a.hadm_id,
    a.los_days,
    a.aki_diagnosis_type,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM
    admissions_with_aki a
  LEFT JOIN
    imaging_studies i
  ON
    a.hadm_id = i.hadm_id
),

los_groups AS (
  SELECT
    hadm_id,
    imaging_count,
    aki_diagnosis_type,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM
    admissions_with_imaging
  WHERE
    los_days BETWEEN 1 AND 7
)

SELECT
  aki_diagnosis_type,
  los_group,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(50)] AS median_imaging,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS q1_imaging,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS q3_imaging
FROM
  los_groups
GROUP BY
  aki_diagnosis_type,
  los_group
ORDER BY
  aki_diagnosis_type,
  los_group;