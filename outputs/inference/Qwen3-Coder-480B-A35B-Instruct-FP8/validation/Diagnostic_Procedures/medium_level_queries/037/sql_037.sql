WITH ami_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS ami_type
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
    AND p.anchor_age BETWEEN 43 AND 53
    AND dd.icd_code LIKE 'I21%'
),

radiology_procedures AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS proc_count
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    REGEXP_CONTAINS(LOWER(dp.long_title), r'ct|radiograph|x-ray')
  GROUP BY
    p.hadm_id
),

admission_proc_counts AS (
  SELECT
    a.hadm_id,
    a.ami_type,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other'
    END AS los_group,
    COALESCE(r.proc_count, 0) AS proc_count
  FROM
    ami_admissions a
  LEFT JOIN
    radiology_procedures r
    ON a.hadm_id = r.hadm_id
  WHERE
    a.los_days BETWEEN 1 AND 7
)

SELECT
  ami_type,
  los_group,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS q25,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS q75
FROM
  admission_proc_counts
GROUP BY
  ami_type,
  los_group
ORDER BY
  ami_type,
  los_group;