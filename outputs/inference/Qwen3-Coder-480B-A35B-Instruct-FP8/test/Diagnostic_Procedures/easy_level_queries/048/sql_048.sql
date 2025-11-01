WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),

valve_procedures AS (
  SELECT p.subject_id, p.hadm_id, p.icd_code, p.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN filtered_patients fp ON fp.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(LOWER(d.long_title), r'valve.*(repair|replacement)')
),

procs_per_admission AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS proc_count
  FROM valve_procedures
  GROUP BY hadm_id
)

SELECT
  APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] - APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS iqr
FROM procs_per_admission;