WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.icd_code,
    d.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 51 AND 61
    AND d.icd_code = 'I10.9' -- Acute pancreatitis code
), RadiographyCounts AS (
  SELECT
    pd.subject_id,
    pd.hadm_id,
    COUNT(DISTINCT hc.hcpcs_cd) AS radiography_ct_count
  FROM PatientDiagnosis AS pd
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
    ON pd.hadm_id = hc.hadm_id
  WHERE
    hc.hcpcs_cd LIKE '77%' -- Radiography/Fluoroscopy codes
  GROUP BY
    pd.subject_id,
    pd.hadm_id
), CTCounts AS (
  SELECT
    pd.subject_id,
    pd.hadm_id,
    COUNT(DISTINCT hc.hcpcs_cd) AS ct_count
  FROM PatientDiagnosis AS pd
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
    ON pd.hadm_id = hc.hadm_id
  WHERE
    hc.hcpcs_cd LIKE '75%' -- CT codes
  GROUP BY
    pd.subject_id,
    pd.hadm_id
), CombinedCounts AS (
  SELECT
    pd.subject_id,
    pd.hadm_id,
    pd.admittime,
    pd.dischtime,
    pd.seq_num,
    COALESCE(rc.radiography_ct_count, 0) AS radiography_ct_count,
    COALESCE(ct.ct_count, 0) AS ct_count,
    (COALESCE(rc.radiography_ct_count, 0) + COALESCE(ct.ct_count, 0)) AS total_radiography_ct_count
  FROM PatientDiagnosis AS pd
  LEFT JOIN RadiographyCounts AS rc
    ON pd.subject_id = rc.subject_id AND pd.hadm_id = rc.hadm_id
  LEFT JOIN CTCounts AS ct
    ON pd.subject_id = ct.subject_id AND pd.hadm_id = ct.hadm_id
)
SELECT
  CASE
    WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3
    THEN '1-3 days'
    WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7
    THEN '4-7 days'
    ELSE 'Other'
  END AS los_group,
  CASE
    WHEN seq_num = 1
    THEN 'Primary'
    ELSE 'Secondary'
  END AS diagnosis_type,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(total_radiography_ct_count) AS mean_radiography_ct_count
FROM CombinedCounts
GROUP BY
  los_group,
  diagnosis_type
ORDER BY
  los_group,
  diagnosis_type;