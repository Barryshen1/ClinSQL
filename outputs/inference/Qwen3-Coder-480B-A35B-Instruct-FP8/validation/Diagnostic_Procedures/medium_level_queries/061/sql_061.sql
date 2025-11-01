WITH aki_admissions AS (
  -- Identify admissions with AKI diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    di.seq_num,
    CASE
      WHEN di.seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    -- AKI ICD codes
    (d.icd_version = 9 AND d.icd_code LIKE '584%')
    OR
    (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
),

filtered_patients AS (
  -- Filter patients by gender and age
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
),

imaging_counts AS (
  -- Count imaging studies per admission
  SELECT
    aa.hadm_id,
    aa.los_days,
    aa.diagnosis_type,
    COUNT(hc.hcpcs_cd) AS imaging_count
  FROM
    aki_admissions aa
  JOIN
    filtered_patients fp
    ON aa.subject_id = fp.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.hcpcsevents hc
    ON aa.hadm_id = hc.hadm_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.d_hcpcs dh
    ON hc.hcpcs_cd = dh.code
  WHERE
    dh.long_description LIKE '%Diagnostic Imaging%'
    AND aa.los_days BETWEEN 1 AND 7
  GROUP BY
    aa.hadm_id, aa.los_days, aa.diagnosis_type
),

stratified_data AS (
  SELECT
    imaging_count,
    diagnosis_type,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM
    imaging_counts
)

SELECT
  los_group,
  diagnosis_type,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS q3
FROM
  stratified_data
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group,
  diagnosis_type
ORDER BY
  los_group,
  diagnosis_type;